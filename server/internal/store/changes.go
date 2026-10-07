package store

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// The change log: every item added, changed or removed, numbered, so a client
// can ask "what happened since change 18,342?" and get exactly that — CloudKit's
// change token, for this library.
//
// Clients used to re-read the newest 400 rows of each library and walk every
// library in full once a week, because a re-read of the newest rows cannot see
// a deletion, a rename or an edit. The log sees all three.
//
// Written by triggers rather than by each writer. There are a dozen writers —
// the scanner, the import, repairs, edits, watch state, artwork — and a writer
// that forgot to log would be a client that silently drifts. A trigger cannot
// be forgotten.

const changeLogDDL = `
CREATE TABLE IF NOT EXISTS change_log (
    seq     INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id TEXT NOT NULL,
    removed INTEGER NOT NULL DEFAULT 0,
    at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
)`

// Each trigger is one statement; schema.sql cannot hold them, since it is
// split on semicolons and a trigger body contains them.
var changeTriggers = []string{
	`CREATE INDEX IF NOT EXISTS change_log_item ON change_log(item_id, seq)`,
	`CREATE TRIGGER IF NOT EXISTS change_item_insert AFTER INSERT ON item BEGIN
	   INSERT INTO change_log (item_id) VALUES (NEW.id); END`,
	`CREATE TRIGGER IF NOT EXISTS change_item_delete AFTER DELETE ON item BEGIN
	   INSERT INTO change_log (item_id, removed) VALUES (OLD.id, 1); END`,
	`CREATE TRIGGER IF NOT EXISTS change_userdata_insert AFTER INSERT ON user_data BEGIN
	   INSERT INTO change_log (item_id) VALUES (NEW.item_id); END`,
	`CREATE TRIGGER IF NOT EXISTS change_userdata_delete AFTER DELETE ON user_data BEGIN
	   INSERT INTO change_log (item_id) VALUES (OLD.item_id); END`,
	// A new poster is a changed item to anyone drawing it.
	`CREATE TRIGGER IF NOT EXISTS change_image_insert AFTER INSERT ON image BEGIN
	   INSERT INTO change_log (item_id) VALUES (NEW.item_id); END`,
	`CREATE TRIGGER IF NOT EXISTS change_image_delete AFTER DELETE ON image BEGIN
	   INSERT INTO change_log (item_id) VALUES (OLD.item_id); END`,
}

// ensureChangeLog creates the log and its triggers; idempotent.
func ensureChangeLog(db *sql.DB) error {
	if _, err := db.Exec(changeLogDDL); err != nil {
		return fmt.Errorf("change log: %w", err)
	}
	for _, stmt := range changeTriggers {
		if _, err := db.Exec(stmt); err != nil {
			return fmt.Errorf("change log trigger: %w", err)
		}
	}
	// Updates log only when a value actually differs. The scanner and the
	// repairs rewrite rows with what they already hold, thousands at a time;
	// logged, every client would re-read them after every scan. Rebuilt on
	// each start from the table's own columns, so a column added later is
	// watched too.
	for _, t := range []struct{ table, key, name string }{
		{"item", "id", "change_item_update"},
		{"user_data", "item_id", "change_userdata_update"},
	} {
		when, err := differs(db, t.table, "updated_at", "source", "session_id")
		if err != nil {
			return err
		}
		db.Exec(`DROP TRIGGER IF EXISTS ` + t.name)
		if _, err := db.Exec(`CREATE TRIGGER ` + t.name + ` AFTER UPDATE ON ` + t.table +
			` WHEN ` + when + ` BEGIN INSERT INTO change_log (item_id) VALUES (NEW.` + t.key + `); END`); err != nil {
			return fmt.Errorf("change log trigger: %w", err)
		}
	}
	// The first number handed out is 1, never 0: a client holding 0 is a
	// client with no token, and must not be mistaken for one that is current.
	db.Exec(`INSERT INTO change_log (item_id) SELECT '' WHERE NOT EXISTS (SELECT 1 FROM sqlite_sequence WHERE name = 'change_log')`)
	return nil
}

// differs is "OLD.a IS NOT NEW.a OR ..." over a table's columns.
func differs(db *sql.DB, table string, skip ...string) (string, error) {
	rows, err := db.Query(`SELECT name FROM pragma_table_info(?)`, table)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	var parts []string
	for rows.Next() {
		var col string
		rows.Scan(&col)
		skipped := false
		for _, s := range skip {
			skipped = skipped || s == col
		}
		if !skipped {
			parts = append(parts, "OLD."+col+" IS NOT NEW."+col)
		}
	}
	if len(parts) == 0 {
		return "", fmt.Errorf("no columns in %s", table)
	}
	return strings.Join(parts, " OR "), rows.Err()
}

// Changes is one page of the log.
type Changes struct {
	// Next is the token to ask with next time.
	Next int64
	// Reset means the token is older than the log reaches, or there was none:
	// read everything once, then carry on from Next.
	Reset   bool
	Changed []string
	Removed []string
	// More means the page was cut at the limit; ask again straight away.
	More bool
}

// LatestChange is the newest change number, 0 on an empty log.
// Read from the AUTOINCREMENT counter, which never goes back — not from the
// rows, which trimming removes.
func (s *Store) LatestChange() int64 {
	var n sql.NullInt64
	s.DB.QueryRow(`SELECT seq FROM sqlite_sequence WHERE name = 'change_log'`).Scan(&n)
	return n.Int64
}

const metaChangeFloor = "change_floor"

// ChangesSince lists the items changed after `since`, each once, in the
// order of their last change. An item changed and then removed is reported
// removed; removed and then re-added (a file put back) is reported changed.
func (s *Store) ChangesSince(since int64, limit int) (Changes, error) {
	latest := s.LatestChange()
	floorText, _ := s.Meta(metaChangeFloor)
	var floor int64
	fmt.Sscan(floorText, &floor)
	if since <= 0 || since < floor || since > latest {
		// No token, one from before the log was trimmed, or one from another
		// database (a restore, a reinstall): the client cannot trust what it
		// holds, so it reads everything once.
		return Changes{Next: latest, Reset: true}, nil
	}
	if limit <= 0 {
		limit = 1000
	}
	rows, err := s.DB.Query(`
		SELECT item_id, removed, seq FROM change_log
		WHERE seq IN (SELECT max(seq) FROM change_log WHERE seq > ? AND item_id <> '' GROUP BY item_id)
		ORDER BY seq LIMIT ?`, since, limit+1)
	if err != nil {
		return Changes{}, err
	}
	defer rows.Close()
	out := Changes{Next: latest}
	n := 0
	for rows.Next() {
		var id string
		var removed int
		var seq int64
		if err := rows.Scan(&id, &removed, &seq); err != nil {
			return Changes{}, err
		}
		if n++; n > limit {
			out.More = true
			break
		}
		out.Next = seq
		if removed == 1 {
			out.Removed = append(out.Removed, id)
		} else {
			out.Changed = append(out.Changed, id)
		}
	}
	if !out.More {
		out.Next = latest
	}
	return out, rows.Err()
}

// WaitForChange returns as soon as the log moves past `since`, or after
// `wait`. A long poll: the server is on this Mac or the home network, so one
// request held open costs nothing, and a change reaches the client within a
// second rather than at its next poll.
func (s *Store) WaitForChange(since int64, wait time.Duration, done <-chan struct{}) int64 {
	deadline := time.Now().Add(wait)
	for {
		if latest := s.LatestChange(); latest > since || time.Now().After(deadline) {
			return latest
		}
		select {
		case <-done:
			return s.LatestChange()
		case <-time.After(750 * time.Millisecond):
		}
	}
}

// TrimChanges keeps the last 30 days and at most 500,000 entries. Clients
// whose token falls behind the trimmed point are told to read everything.
func (s *Store) TrimChanges() error {
	cutoff := time.Now().UTC().AddDate(0, 0, -30).Format(time.RFC3339)
	var keepFrom sql.NullInt64
	s.DB.QueryRow(`SELECT max(seq) - 500000 FROM change_log`).Scan(&keepFrom)
	res, err := s.DB.Exec(`DELETE FROM change_log WHERE at < ? OR seq <= ?`, cutoff, keepFrom.Int64)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n > 0 {
		var min sql.NullInt64
		s.DB.QueryRow(`SELECT min(seq) FROM change_log`).Scan(&min)
		floor := min.Int64 - 1
		if !min.Valid {
			floor = s.LatestChange()
		}
		return s.SetMeta(metaChangeFloor, fmt.Sprint(floor))
	}
	return nil
}
