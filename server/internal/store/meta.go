package store

import (
	"database/sql"
	"errors"
)

// Meta reads one key from the meta table, or "" where it was never written.
func (s *Store) Meta(key string) (string, error) {
	var value string
	err := s.DB.QueryRow(`SELECT value FROM meta WHERE key = ?`, key).Scan(&value)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	return value, err
}

// SetMeta writes one key, replacing what was there.
func (s *Store) SetMeta(key, value string) error {
	_, err := s.DB.Exec(`
		INSERT INTO meta (key, value) VALUES (?, ?)
		ON CONFLICT(key) DO UPDATE SET value = excluded.value`, key, value)
	return err
}

// MetaRepairedAt is when a scan last rewrote rows the client already holds —
// a film folded into a show, a clip unfolded into its folder. A client that
// syncs incrementally only sees new ids; this tells it there is more to see.
const MetaRepairedAt = "repaired_at"
