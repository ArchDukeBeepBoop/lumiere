package store

import (
	"database/sql"
	"errors"
	"time"
)

// Writing watch state — the only place this server writes anything a person
// would miss.
//
// Every write here sets source='local', which is what makes Batch 1's
// overwriteLocal rule mean something: a re-import must not erase an evening's
// viewing, and it can only tell what to keep because these rows say who wrote
// them.

// Progress is one report from the player.
type Progress struct {
	ItemID        string
	PositionTicks int64
	SessionID     string
	Stopped       bool
}

// RecordProgress saves a position, subject to the session ordering rule.
//
// Reports arrive late and out of order — Lumiere queues them while the server
// is unreachable and replays them on reconnect — and they carry no timestamp,
// only a PlaySessionId. So ordering is done on sessions: within one the client
// replays in order and everything is accepted; between two, the session that
// started later wins.
//
// The naive reading of "last write wins by position" — keep whichever position
// is larger — is wrong in a way worth naming, because it looks safe. It does
// stop a stale replay from rewinding a resume point, but it also makes
// rewatching impossible: start a film again from the beginning, stop at two
// minutes, and a rule that prefers the larger number silently restores the
// forty-minute position from last time.
func (s *Store) RecordProgress(p Progress) error {
	if p.ItemID == "" {
		return errors.New("no item")
	}
	now := time.Now().UTC()
	stamp := now.Format(time.RFC3339Nano)

	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if p.SessionID != "" {
		if _, err := tx.Exec(
			`INSERT OR IGNORE INTO play_session (session_id, item_id, started_at)
			 VALUES (?,?,?)`, p.SessionID, p.ItemID, stamp); err != nil {
			return err
		}
		fresher, err := supersedes(tx, p.ItemID, p.SessionID)
		if err != nil {
			return err
		}
		if !fresher {
			// A replayed report from a session that has already been overtaken.
			// Dropping it is the point of the whole mechanism.
			return nil
		}
	}

	_, err = tx.Exec(`
		INSERT INTO user_data (item_id, played, play_count, position_ticks,
		                       is_favorite, last_played, updated_at, source, session_id)
		VALUES (?, 0, 0, ?, 0, ?, ?, 'local', ?)
		ON CONFLICT(item_id) DO UPDATE SET
		    position_ticks = excluded.position_ticks,
		    last_played    = excluded.last_played,
		    updated_at     = excluded.updated_at,
		    source         = 'local',
		    session_id     = excluded.session_id`,
		p.ItemID, p.PositionTicks, stamp, stamp, nullable(p.SessionID))
	if err != nil {
		return err
	}
	return tx.Commit()
}

// supersedes reports whether this session is at least as recent as the one that
// last wrote the row.
//
// A row written by no session — an import, or a report with no PlaySessionId —
// is always overwritable: it carries no ordering information to respect.
func supersedes(tx *sql.Tx, itemID, sessionID string) (bool, error) {
	var previous sql.NullString
	err := tx.QueryRow(`SELECT session_id FROM user_data WHERE item_id = ?`,
		itemID).Scan(&previous)
	if errors.Is(err, sql.ErrNoRows) {
		// Nothing recorded yet: nothing to defend.
		return true, nil
	}
	if err != nil {
		return false, err
	}
	if !previous.Valid || previous.String == "" {
		return true, nil
	}
	if previous.String == sessionID {
		return true, nil
	}

	var mine, theirs sql.NullString
	if err := tx.QueryRow(`SELECT started_at FROM play_session WHERE session_id = ?`,
		sessionID).Scan(&mine); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return false, err
	}
	if err := tx.QueryRow(`SELECT started_at FROM play_session WHERE session_id = ?`,
		previous.String).Scan(&theirs); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return false, err
	}
	// An unknown previous session cannot be defended; an unknown incoming one
	// cannot be trusted over a known one.
	if !theirs.Valid {
		return true, nil
	}
	if !mine.Valid {
		return false, nil
	}
	return mine.String >= theirs.String, nil
}

// SetPlayed marks an item watched or unwatched.
//
// Unwatching zeroes the position and the play count and drops the last-played
// date — verified in the capture (§12.5), and it is how Lumiere resets a resume
// point. A server that leaves the position behind makes a "watched" episode
// resume at its final second, which is the exact bug fixed on the client side
// this week.
func (s *Store) SetPlayed(itemID string, played bool) error {
	// A folder — a season, a series, a collection — marks everything playable
	// under it, which is Jellyfin's contract for this route and what a person
	// means by "mark the season watched". The row for the folder itself is
	// written too, so the tick shows on it without a recount.
	var isFolder int
	var kind string
	s.DB.QueryRow(`SELECT is_folder, type FROM item WHERE id = ?`, itemID).Scan(&isFolder, &kind)
	// A collection's members are links, not children: each takes the mark as
	// if it had been marked itself, a show down to its episodes.
	if kind == "BoxSet" {
		for _, member := range s.linkedMembers(itemID) {
			if err := s.SetPlayed(member, played); err != nil {
				return err
			}
		}
		return s.setPlayedRow(itemID, played)
	}
	if isFolder == 1 {
		ids, err := s.Descendants(itemID)
		if err != nil {
			return err
		}
		for _, id := range ids {
			if id == itemID {
				continue
			}
			// Seasons under a series take the mark too — the tick shows on
			// them. Extras do not: a creditless opening is not something
			// anyone watched.
			var extra sql.NullString
			s.DB.QueryRow(`SELECT extra_type FROM item WHERE id = ?`, id).Scan(&extra)
			if extra.Valid {
				continue
			}
			if err := s.setPlayedRow(id, played); err != nil {
				return err
			}
		}
	}
	return s.setPlayedRow(itemID, played)
}

func (s *Store) setPlayedRow(itemID string, played bool) error {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	if !played {
		_, err := s.DB.Exec(`
			INSERT INTO user_data (item_id, played, play_count, position_ticks,
			                       is_favorite, last_played, updated_at, source)
			VALUES (?, 0, 0, 0, 0, NULL, ?, 'local')
			ON CONFLICT(item_id) DO UPDATE SET
			    played = 0, play_count = 0, position_ticks = 0,
			    last_played = NULL, updated_at = excluded.updated_at,
			    source = 'local', session_id = NULL`, itemID, now)
		return err
	}
	_, err := s.DB.Exec(`
		INSERT INTO user_data (item_id, played, play_count, position_ticks,
		                       is_favorite, last_played, updated_at, source)
		VALUES (?, 1, 1, 0, 0, ?, ?, 'local')
		ON CONFLICT(item_id) DO UPDATE SET
		    played = 1,
		    play_count = user_data.play_count + 1,
		    position_ticks = 0,
		    last_played = excluded.last_played,
		    updated_at = excluded.updated_at,
		    source = 'local'`, itemID, now, now)
	return err
}

// SetFavorite toggles the heart. It touches nothing else: favouriting an
// episode must not disturb where you were in it.
func (s *Store) SetFavorite(itemID string, favorite bool) error {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	_, err := s.DB.Exec(`
		INSERT INTO user_data (item_id, played, play_count, position_ticks,
		                       is_favorite, updated_at, source)
		VALUES (?, 0, 0, 0, ?, ?, 'local')
		ON CONFLICT(item_id) DO UPDATE SET
		    is_favorite = excluded.is_favorite,
		    updated_at = excluded.updated_at,
		    source = 'local'`, itemID, boolInt(favorite), now)
	return err
}

// UserDataFor reads back what was just written, for the response body.
func (s *Store) UserDataFor(itemID string) (UserData, error) {
	var u UserData
	var lastPlayed sql.NullString
	err := s.DB.QueryRow(
		`SELECT played, play_count, position_ticks, is_favorite, last_played
		 FROM user_data WHERE item_id = ?`, itemID,
	).Scan(&u.Played, &u.PlayCount, &u.PositionTicks, &u.IsFavorite, &lastPlayed)
	if errors.Is(err, sql.ErrNoRows) {
		return UserData{}, nil
	}
	u.LastPlayed = lastPlayed.String
	return u, err
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}
