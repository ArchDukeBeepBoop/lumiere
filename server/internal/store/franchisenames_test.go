package store

import "testing"

func TestFranchiseNamingReachesTheLibrarysFolders(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO library_folder (view_id, folder_id) VALUES ('adult', 'f1'), ('anime', 'f2')`)
	s.DB.Exec(`INSERT INTO item (id, type, name, path, is_folder) VALUES
		('show', 'Series', 'Star Swap', '/m/Adult/Hoshi Twins', 1), ('film', 'Movie', 'x', '/m/F/Name (2001).mkv', 0)`)
	s.SetFranchiseNaming(map[string]string{"adult": "folder", "anime": "romaji", "other": "nonsense"})
	got := s.FranchiseNaming()
	if got["f1"] != "folder" || got["f2"] != "romaji" || got["other"] != "" {
		t.Fatalf("naming: %v", got)
	}
	if s.FolderNameOf("show") != "Hoshi Twins" || s.FolderNameOf("film") != "Name (2001)" {
		t.Fatalf("folder names: %q %q", s.FolderNameOf("show"), s.FolderNameOf("film"))
	}
}
