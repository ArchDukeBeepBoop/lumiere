package api

import (
	"sync"

	"lumiere-server/internal/store"
)

// The library view each item belongs to. Items carry the folder id; clients
// know libraries by the view id UserViews lists. Loaded at start and after a
// scan — libraries are added rarely, and ToWire runs for every row.
var libraryViews struct {
	sync.RWMutex
	byFolder map[string]string
}

// LoadLibraryViews reads the folder → view map.
func LoadLibraryViews(s *store.Store) {
	rows, err := s.DB.Query(`SELECT folder_id, view_id FROM library_folder`)
	if err != nil {
		return
	}
	defer rows.Close()
	m := map[string]string{}
	for rows.Next() {
		var folder, view string
		if rows.Scan(&folder, &view) == nil {
			m[folder] = view
		}
	}
	libraryViews.Lock()
	libraryViews.byFolder = m
	libraryViews.Unlock()
}

// LibraryView is the view id for a folder id, or the folder id itself.
func LibraryView(folderID string) string {
	if folderID == "" {
		return ""
	}
	libraryViews.RLock()
	defer libraryViews.RUnlock()
	if v, ok := libraryViews.byFolder[folderID]; ok {
		return v
	}
	return folderID
}
