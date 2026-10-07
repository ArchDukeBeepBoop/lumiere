package store

import (
	"database/sql"
	"path/filepath"
	"testing"
)

func TestTokensAreNotStoredInTheClear(t *testing.T) {
	s := openTempStore(t)
	if _, err := s.DB.Exec(
		`INSERT INTO account (id, username, password_hash, updated_at) VALUES ('a1','someone','x','2026-01-01')`,
	); err != nil {
		t.Fatal(err)
	}

	const token = "0123456789abcdef0123456789abcdef"
	if err := s.IssueToken(token, "a1", SessionInfo{Device: "Mac"}); err != nil {
		t.Fatal(err)
	}

	var stored string
	if err := s.DB.QueryRow(`SELECT token FROM token`).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if stored == token {
		t.Fatal("the token is in the database exactly as issued")
	}
	if stored != HashToken(token) {
		t.Fatalf("stored value is neither the token nor its hash: %q", stored)
	}

	sess, err := s.LookupToken(token)
	if err != nil {
		t.Fatalf("the issued token does not authenticate: %v", err)
	}
	if sess.AccountID != "a1" {
		t.Errorf("account = %q, want a1", sess.AccountID)
	}
	if sess.Token != token {
		t.Errorf("session token = %q, want the credential the caller used", sess.Token)
	}

	if _, err := s.LookupToken("ffffffffffffffffffffffffffffffff"); err != ErrNoAccount {
		t.Errorf("a token nobody issued resolved to %v, want ErrNoAccount", err)
	}
}

// A database written before tokens were hashed must keep its sessions working:
// the alternative is signing the owner out of the app they are using.
func TestExistingPlaintextTokensAreConvertedInPlace(t *testing.T) {
	dir := t.TempDir()
	const token = "aaaabbbbccccddddeeeeffff00001111"

	first, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := first.DB.Exec(
		`INSERT INTO account (id, username, password_hash, updated_at) VALUES ('a1','someone','x','2026-01-01')`,
	); err != nil {
		t.Fatal(err)
	}
	// Written the old way, straight in.
	if _, err := first.DB.Exec(
		`INSERT INTO token (token, account_id, created_at, last_seen)
		 VALUES (?, 'a1', '2026-01-01', '2026-01-01')`, token,
	); err != nil {
		t.Fatal(err)
	}
	first.Close()

	second, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer second.Close()

	var stored string
	if err := second.DB.QueryRow(`SELECT token FROM token`).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if stored == token {
		t.Fatal("an existing plaintext token was left in the clear")
	}
	if _, err := second.LookupToken(token); err != nil {
		t.Fatalf("converting logged the client out: %v", err)
	}

	// And again: converting twice must not turn a hash into a hash of a hash.
	third, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer third.Close()
	if _, err := third.LookupToken(token); err != nil {
		t.Fatalf("a second open broke the session: %v", err)
	}
}

func openTempStore(t *testing.T) *Store {
	t.Helper()
	s, err := Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	var _ *sql.DB = s.DB
	_ = filepath.Join
	return s
}
