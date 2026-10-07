package store

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"time"
)

// ErrNoAccount is returned rather than sql.ErrNoRows so callers do not have to
// import database/sql to tell "wrong username" from "database broke" — a
// distinction that decides between a 401 and a 500.
var ErrNoAccount = errors.New("no such account")

// ErrNoImage is its counterpart on the artwork path: an item with no picture of
// the kind asked for is an ordinary answer, not a failure.
var ErrNoImage = errors.New("no such image")

// ErrNoItem is the same idea for items: asking for one that is not here is an
// ordinary 404, not a server fault.
var ErrNoItem = errors.New("no such item")

type Account struct {
	ID           string
	Username     string
	PasswordHash string
}

// AccountByName looks an account up case-insensitively.
//
// Jellyfin keeps a NormalizedUsername column for exactly this, and its clients
// let people type their name however they remember it. Matching case-sensitively
// here would reject a password that is in fact correct, which is the most
// confusing failure this endpoint can produce.
func (s *Store) AccountByName(username string) (Account, error) {
	var a Account
	var hash sql.NullString
	err := s.DB.QueryRow(
		`SELECT id, username, password_hash FROM account
		 WHERE lower(username) = lower(?)`, username,
	).Scan(&a.ID, &a.Username, &hash)
	if errors.Is(err, sql.ErrNoRows) {
		return Account{}, ErrNoAccount
	}
	a.PasswordHash = hash.String
	return a, err
}

// AnyAccount reports whether any account exists at all.
//
// Used to tell "wrong password" from "the import has never run", which are the
// same 401 to the client and completely different problems for whoever is
// reading the log.
func (s *Store) AnyAccount() (bool, error) {
	var n int
	err := s.DB.QueryRow(`SELECT count(*) FROM account`).Scan(&n)
	return n > 0, err
}

type Session struct {
	Token     string
	AccountID string
	DeviceID  string
}

// IssueToken records a token against an account and a device.
//
// One row per sign-in rather than one per device: Lumiere signs in once and
// keeps the token indefinitely, so rows accumulate only when someone actually
// signs in again, and keeping the old row means an older copy of the app that
// still holds a valid token is not silently logged out.
// HashToken is what the token column actually holds.
//
// SHA-256, unsalted and uniterated — deliberately, and the reason is worth
// stating because it looks like the wrong answer next to the password hashing
// two files over. A password is low-entropy and guessable, so it needs a slow
// function and a salt to make each guess expensive. A token here is 128 bits
// from crypto/rand: there is nothing to guess, no dictionary to try, and no two
// accounts can collide. Stretching it would cost every request the CPU of a
// PBKDF2 round — this runs on *every* range request of a playing film — and buy
// nothing.
//
// What it does buy is that the database no longer holds anything usable. A
// backup, a copied file, a stray Time Machine snapshot: none of them now carry a
// credential that works.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (s *Store) IssueToken(token, accountID string, c SessionInfo) error {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	_, err := s.DB.Exec(
		`INSERT INTO token (token, account_id, device_id, device, client, version,
		                    created_at, last_seen)
		 VALUES (?,?,?,?,?,?,?,?)`,
		HashToken(token), accountID, nullable(c.DeviceID), nullable(c.Device),
		nullable(c.Client), nullable(c.Version), now, now)
	return err
}

// SessionInfo is the device half of a sign-in, straight off the header.
type SessionInfo struct {
	Client   string
	Device   string
	DeviceID string
	Version  string
}

// LookupToken resolves a token to its account, or ErrNoAccount.
//
// last_seen is deliberately not written here. This runs on every request
// including every range request of a playing film — four per playback in the
// capture — and a write per request would turn a read-only path into a stream of
// transactions competing with the import for the same file.
func (s *Store) LookupToken(token string) (Session, error) {
	var sess Session
	var device sql.NullString
	// The column holds a hash, so the presented token is hashed to look it up.
	// Nothing is compared in Go: the index does the work, and there is no
	// timing signal worth chasing in an indexed lookup of a 256-bit key.
	err := s.DB.QueryRow(
		`SELECT account_id, device_id FROM token WHERE token = ?`, HashToken(token),
	).Scan(&sess.AccountID, &device)
	if errors.Is(err, sql.ErrNoRows) {
		return Session{}, ErrNoAccount
	}
	// The token the caller authenticated with, not the row's hash — the field
	// means "the credential this session is using", and handing back a hash
	// would be a value that looks usable and is not.
	sess.Token = token
	sess.DeviceID = device.String
	return sess, err
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// AccountByID is the token path's lookup: a session names an account id, and
// serving a user object needs the name that goes with it.
func (s *Store) AccountByID(id string) (Account, error) {
	var a Account
	var hash sql.NullString
	err := s.DB.QueryRow(
		`SELECT id, username, password_hash FROM account WHERE id = ?`, id,
	).Scan(&a.ID, &a.Username, &hash)
	if errors.Is(err, sql.ErrNoRows) {
		return Account{}, ErrNoAccount
	}
	a.PasswordHash = hash.String
	return a, err
}

// Identification is what the client learned from a metadata provider.
type Identification struct {
	Name        string
	Year        *int
	ProviderIDs map[string]string
}

// ApplyIdentification writes a corrected match onto an item.
//
// One transaction: a title changed without its provider ids, or ids written
// against a name that failed to save, is a half-identified item that looks
// finished. Provider ids live in item_value under a `provider:` kind rather than
// in a new table — the shape already exists, and this is the first thing in this
// server that has ever needed them.
func (s *Store) ApplyIdentification(itemID string, id Identification) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var exists int
	if err := tx.QueryRow(`SELECT count(*) FROM item WHERE id = ?`, itemID).Scan(&exists); err != nil {
		return err
	}
	if exists == 0 {
		return ErrNoItem
	}

	if id.Name != "" {
		// sort_name follows the name. Leaving the old one behind would file the
		// corrected title under the wrong letter, which is the sort of quiet
		// wrongness that outlives the person who noticed the title was bad.
		if _, err := tx.Exec(
			`UPDATE item SET name = ?, sort_name = ? WHERE id = ?`,
			id.Name, id.Name, itemID,
		); err != nil {
			return err
		}
	}
	if id.Year != nil {
		if _, err := tx.Exec(
			`UPDATE item SET production_year = ? WHERE id = ?`, *id.Year, itemID,
		); err != nil {
			return err
		}
	}

	// Replaced, not merged: identifying means what was there is wrong.
	if _, err := tx.Exec(
		`DELETE FROM item_value WHERE item_id = ? AND kind LIKE 'provider:%'`, itemID,
	); err != nil {
		return err
	}
	for key, value := range id.ProviderIDs {
		if key == "" || value == "" {
			continue
		}
		if _, err := tx.Exec(
			`INSERT OR REPLACE INTO item_value (item_id, kind, value) VALUES (?,?,?)`,
			itemID, "provider:"+key, value,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// SetPrimaryImage points an item's poster at a file this server fetched.
// SetImage points an item at a picture of any kind.
//
// SetPrimaryImage is this with the kind fixed; the artwork picker needs
// backdrops and thumbs too, and hardcoding Primary was why it could only ever
// have replaced one of the four.
func (s *Store) SetImage(itemID, kind, path, tag string, size int) error {
	_, err := s.DB.Exec(
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES (?,?,?,?,?)
		 ON CONFLICT(item_id, kind, idx) DO UPDATE SET path = excluded.path, tag = excluded.tag`,
		itemID, kind, 0, path, tag,
	)
	return err
}

func (s *Store) SetPrimaryImage(itemID, path, tag string, size int) error {
	_, err := s.DB.Exec(
		`INSERT INTO image (item_id, kind, idx, path, tag) VALUES (?,?,?,?,?)
		 ON CONFLICT(item_id, kind, idx) DO UPDATE SET path = excluded.path, tag = excluded.tag`,
		itemID, "Primary", 0, path, tag,
	)
	return err
}

// ErrAccountsExist refuses the first-run account once there is one: the setup
// endpoint is unauthenticated, so it may only ever make the first.
var ErrAccountsExist = errors.New("an account already exists")

// CreateFirstAccount makes the server's first account. The hash is in the
// same PBKDF2 format the importer carries, so one verifier serves both.
func (s *Store) CreateFirstAccount(id, username, hash string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var n int
	if err := tx.QueryRow(`SELECT count(*) FROM account`).Scan(&n); err != nil {
		return err
	}
	if n > 0 {
		return ErrAccountsExist
	}
	if _, err := tx.Exec(`INSERT INTO account (id, username, password_hash, updated_at) VALUES (?, ?, ?, ?)`,
		id, username, hash, time.Now().UTC().Format(time.RFC3339)); err != nil {
		return err
	}
	return tx.Commit()
}

// SetPasswordHash replaces an account's password.
func (s *Store) SetPasswordHash(id, hash string) error {
	_, err := s.DB.Exec(`UPDATE account SET password_hash = ?, updated_at = ? WHERE id = ?`,
		hash, time.Now().UTC().Format(time.RFC3339), id)
	return err
}
