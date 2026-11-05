package scanner

import (
	"io"
	"log/slog"
	"testing"
)

func TestARemakeIsFiledApartFromItsOriginal(t *testing.T) {
	s := testScanner(t)
	db := s.Store.DB
	for _, q := range []string{
		`INSERT INTO item (id, type, name, path, is_folder) VALUES ('anime', 'Folder', 'Anime', '/M/Anime', 1)`,
		`INSERT INTO item (id, type, name, library_id, path, production_year, is_folder, date_created) VALUES
			('kenshin', 'Series', 'Rurouni Kenshin', 'anime', '/M/Anime/Rurouni Kenshin', 1996, 1, '2026-07-01')`,
		`INSERT INTO item (id, type, name, library_id, parent_id, series_id, index_number, is_folder, date_created) VALUES
			('s1', 'Season', 'Season 1', 'anime', 'kenshin', 'kenshin', 1, 1, '2026-07-01'),
			('s2', 'Season', 'Season 2', 'anime', 'kenshin', 'kenshin', 2, 1, '2026-07-01')`,
		`INSERT INTO item (id, type, name, library_id, parent_id, season_id, series_id, parent_index_number, index_number, path, is_folder, date_created) VALUES
			('old1', 'Episode', 'Ep 1', 'anime', 's1', 's1', 'kenshin', 1, 1, '/M/Anime/Rurouni Kenshin (1996)/Season 1/e1.mkv', 0, '2026-10-31'),
			('old2', 'Episode', 'Ep 2', 'anime', 's2', 's2', 'kenshin', 2, 1, '/M/Anime/Rurouni Kenshin (1996)/Season 2/e1.mkv', 0, '2026-10-31'),
			('new1', 'Episode', 'Ep 1', 'anime', 's1', 's1', 'kenshin', 1, 1, '/M/Anime/Rurouni Kenshin (2023)/Season 1/e1.mkv', 0, '2026-10-31'),
			('new2', 'Episode', 'Ep 2', 'anime', 's1', 's1', 'kenshin', 1, 2, '/M/Anime/Rurouni Kenshin (2023)/Season 1/e2.mkv', 0, '2026-10-31')`,
	} {
		if _, err := db.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	n, err := splitYearFolders(db, slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err != nil || n != 1 {
		t.Fatalf("made %d (%v), want the remake", n, err)
	}
	var keptPath, remake, remakeYear, oldSeries string
	db.QueryRow(`SELECT path FROM item WHERE id = 'kenshin'`).Scan(&keptPath)
	db.QueryRow(`SELECT series_id FROM item WHERE id = 'new1'`).Scan(&remake)
	db.QueryRow(`SELECT production_year FROM item WHERE id = ?`, remake).Scan(&remakeYear)
	db.QueryRow(`SELECT series_id FROM item WHERE id = 'old2'`).Scan(&oldSeries)
	if keptPath != "/M/Anime/Rurouni Kenshin (1996)" || oldSeries != "kenshin" {
		t.Fatalf("the original keeps its own folder: %q %q", keptPath, oldSeries)
	}
	if remake == "kenshin" || remakeYear != "2023" {
		t.Fatalf("the remake is its own show: %q %q", remake, remakeYear)
	}
	var seasons int
	db.QueryRow(`SELECT count(*) FROM item WHERE type = 'Season' AND parent_id = ?`, remake).Scan(&seasons)
	if seasons != 1 {
		t.Fatalf("the remake has its own season 1: %d", seasons)
	}
	if again, _ := splitYearFolders(db, slog.New(slog.NewTextHandler(io.Discard, nil))); again != 0 {
		t.Fatal("once apart, nothing more to do")
	}
}
