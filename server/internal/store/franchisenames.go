package store

import (
	"path/filepath"
	"strings"
)

// How each library wants its franchises named, from the app's per-library
// Title Order: "folder" for one read by folder names, "romaji" for one read
// in romaji; a library not listed keeps the English-first name. Kept as
// "view=mode,view=mode". See anilist.NameFrom.
const metaFranchiseNames = "franchise_names"

// SetFranchiseNaming records the modes, by library view.
func (s *Store) SetFranchiseNaming(modes map[string]string) error {
	var parts []string
	for view, mode := range modes {
		if mode == "folder" || mode == "romaji" {
			parts = append(parts, view+"="+mode)
		}
	}
	return s.SetMeta(metaFranchiseNames, strings.Join(parts, ","))
}

// FranchiseNaming is the modes keyed by physical folder, which is what an
// item's library_id names.
func (s *Store) FranchiseNaming() map[string]string {
	raw, _ := s.Meta(metaFranchiseNames)
	out := map[string]string{}
	for _, part := range strings.Split(raw, ",") {
		view, mode, ok := strings.Cut(part, "=")
		if !ok {
			continue
		}
		out[view] = mode
		folders, _ := s.resolveFolders(view)
		for _, f := range folders {
			out[f] = mode
		}
	}
	return out
}

// FolderNameOf is an item's folder name — a show's folder, a film's file
// without its extension — as the app's folder-name Title Order shows it.
func (s *Store) FolderNameOf(id string) string {
	var path string
	var folder bool
	s.DB.QueryRow(`SELECT COALESCE(path, ''), is_folder FROM item WHERE id = ?`, id).Scan(&path, &folder)
	if path == "" {
		return ""
	}
	name := filepath.Base(path)
	if !folder {
		name = strings.TrimSuffix(name, filepath.Ext(name))
	}
	return name
}
