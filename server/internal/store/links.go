package store

import (
	"crypto/sha256"
	"encoding/hex"
	"time"
)

// Link is membership of a collection or a playlist. See the link table.

// CreateContainer makes a BoxSet or a Playlist and returns its id.
func (s *Store) CreateContainer(kind, name string, memberIDs []string) (string, error) {
	sum := sha256.Sum256([]byte(kind + ":" + name + ":" + time.Now().UTC().String()))
	id := hex.EncodeToString(sum[:16])
	tx, err := s.DB.Begin()
	if err != nil {
		return "", err
	}
	defer tx.Rollback()
	// A collection goes where the others are — see collectionsHome.
	var parent, library string
	if kind == "BoxSet" {
		parent, library = s.collectionsHome(tx)
	}
	if _, err := tx.Exec(`
		INSERT INTO item (id, type, name, sort_name, is_folder, date_created, parent_id, library_id)
		VALUES (?, ?, ?, ?, 1, ?, NULLIF(?, ''), NULLIF(?, ''))`,
		id, kind, name, name, time.Now().UTC().Format(time.RFC3339), parent, library); err != nil {
		return "", err
	}
	for i, member := range memberIDs {
		if _, err := tx.Exec(`
			INSERT OR IGNORE INTO link (parent_id, child_id, position) VALUES (?, ?, ?)`,
			id, member, i); err != nil {
			return "", err
		}
	}
	return id, tx.Commit()
}

// AddLinks appends members, after whatever is there.
func (s *Store) AddLinks(parentID string, childIDs []string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var last int
	tx.QueryRow(`SELECT COALESCE(MAX(position), -1) FROM link WHERE parent_id = ?`, parentID).Scan(&last)
	for i, child := range childIDs {
		if _, err := tx.Exec(`
			INSERT OR IGNORE INTO link (parent_id, child_id, position) VALUES (?, ?, ?)`,
			parentID, child, last+1+i); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) RemoveLinks(parentID string, childIDs []string) error {
	for _, child := range childIDs {
		if _, err := s.DB.Exec(
			`DELETE FROM link WHERE parent_id = ? AND child_id = ?`, parentID, child); err != nil {
			return err
		}
	}
	return nil
}

// DeleteContainer removes a collection or playlist and its links. The members
// are untouched: this app never deletes media.
func (s *Store) DeleteContainer(id string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`DELETE FROM link WHERE parent_id = ?`, id); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM item WHERE id = ? AND type IN ('BoxSet', 'Playlist')`, id); err != nil {
		return err
	}
	return tx.Commit()
}

// IsContainer says whether an id is something with links rather than children.
func (s *Store) IsContainer(id string) bool {
	var kind string
	err := s.DB.QueryRow(`SELECT type FROM item WHERE id = ?`, id).Scan(&kind)
	return err == nil && (kind == "BoxSet" || kind == "Playlist")
}
