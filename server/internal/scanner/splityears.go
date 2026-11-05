package scanner

import (
	"database/sql"
	"fmt"
	"log/slog"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// A show and its remake, filed apart again.
//
// "Rurouni Kenshin (1996)" and "Rurouni Kenshin (2023)" — and Dracula (2013)
// and (2020) — ended up as one show. mergeDuplicateSeries matched a show's
// folder as a prefix of another's ("…/Rurouni Kenshin" begins
// "…/Rurouni Kenshin (2023)/…"), and the scanner matched a new folder to a
// show by name with its year stripped. Both are fixed; this separates the
// shows they already joined. A show whose episodes come from show folders
// naming different years keeps the folder of its own year, and each other
// year becomes a show of its own, seasons and all — unmatched, so the next
// metadata pass names it, and the franchise pass can group the two again as
// what they are: one franchise, two shows.

var folderYear = regexp.MustCompile(`\((\d{4})\)\s*$`)

type yearEpisode struct {
	id, seasonName, created string
	season                  int
}

// splitYearFolders separates them; returns how many shows it made.
func splitYearFolders(db *sql.DB, log *slog.Logger) (int, error) {
	rows, err := db.Query(`
		SELECT e.id, e.path, e.series_id, COALESCE(e.parent_index_number, -1), COALESCE(season.name, ''),
		       root.path, s.library_id, s.name, COALESCE(s.production_year, 0), e.date_created
		FROM item e
		JOIN item s ON s.id = e.series_id AND s.type = 'Series'
		JOIN item root ON root.id = s.library_id
		LEFT JOIN item season ON season.id = e.parent_id AND season.type = 'Season'
		WHERE e.type = 'Episode' AND e.path IS NOT NULL AND e.path <> '' AND root.path IS NOT NULL`)
	if err != nil {
		return 0, err
	}
	type show struct {
		library, name string
		year          int
		folders       map[string][]yearEpisode
	}
	shows := map[string]*show{}
	for rows.Next() {
		var e yearEpisode
		var path, seriesID, root, library, name string
		var year int
		if err := rows.Scan(&e.id, &path, &seriesID, &e.season, &e.seasonName, &root, &library, &name, &year, &e.created); err != nil {
			rows.Close()
			return 0, err
		}
		rel, err := filepath.Rel(root, path)
		if err != nil || strings.HasPrefix(rel, "..") {
			continue
		}
		folder := filepath.Join(root, strings.SplitN(rel, string(filepath.Separator), 2)[0])
		sh := shows[seriesID]
		if sh == nil {
			sh = &show{library: library, name: name, year: year, folders: map[string][]yearEpisode{}}
			shows[seriesID] = sh
		}
		sh.folders[folder] = append(sh.folders[folder], e)
	}
	rows.Close()

	made := 0
	for seriesID, sh := range shows {
		years := map[int]string{}
		for folder := range sh.folders {
			if m := folderYear.FindStringSubmatch(filepath.Base(folder)); m != nil {
				y, _ := strconv.Atoi(m[1])
				years[y] = folder
			}
		}
		if len(years) < 2 {
			continue
		}
		// The show keeps its own year's folder, or else its largest one.
		keep := years[sh.year]
		if keep == "" {
			for _, folder := range years {
				if keep == "" || len(sh.folders[folder]) > len(sh.folders[keep]) {
					keep = folder
				}
			}
		}
		db.Exec(`UPDATE item SET path = ? WHERE id = ?`, keep, seriesID)
		for year, folder := range years {
			if folder == keep {
				continue
			}
			// Named by its own folder: "Star Saga New Testament (2004)" was
			// filed inside "Star Saga: Origins" and is not called that.
			name := strings.TrimSpace(folderYear.ReplaceAllString(filepath.Base(folder), ""))
			if err := splitOff(db, sh.library, name, year, folder, sh.folders[folder]); err != nil {
				return made, err
			}
			made++
			log.Info("repair: a remake filed apart from the original", "show", name, "from", sh.name, "year", year)
		}
		dropEmptySeasons(db, seriesID)
	}
	return made, nil
}

// splitOff makes the show for one year's folder and moves its episodes in.
func splitOff(db *sql.DB, library, name string, year int, folder string, episodes []yearEpisode) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	created := episodes[0].created
	for _, e := range episodes {
		if e.created < created {
			created = e.created
		}
	}
	seriesID := ItemID(fmt.Sprintf("series:%s:%s (%d)", library, name, year))
	if _, err := tx.Exec(`INSERT INTO item (id, type, name, sort_name, library_id, path, production_year, is_folder, date_created)
		VALUES (?, 'Series', ?, ?, ?, ?, ?, 1, ?) ON CONFLICT(id) DO NOTHING`,
		seriesID, name, name, library, folder, year, created); err != nil {
		return err
	}
	for _, e := range episodes {
		seasonName := e.seasonName
		if seasonName == "" {
			seasonName = "Season Unknown"
		}
		seasonID := ItemID("season:" + seriesID + ":" + seasonName)
		var index any
		if e.season >= 0 {
			index = e.season
		}
		if _, err := tx.Exec(`INSERT INTO item (id, type, name, sort_name, library_id, parent_id, series_id, series_name,
				index_number, is_folder, date_created)
			VALUES (?, 'Season', ?, ?, ?, ?, ?, ?, ?, 1, ?) ON CONFLICT(id) DO NOTHING`,
			seasonID, seasonName, seasonName, library, seriesID, seriesID, name, index, created); err != nil {
			return err
		}
		if _, err := tx.Exec(`UPDATE item SET parent_id = ?, season_id = ?, series_id = ? WHERE id = ?`,
			seasonID, seasonID, seriesID, e.id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// dropEmptySeasons removes a show's seasons the split left with nothing.
func dropEmptySeasons(db *sql.DB, seriesID string) {
	db.Exec(`DELETE FROM item WHERE type = 'Season' AND parent_id = ?
		AND NOT EXISTS (SELECT 1 FROM item c WHERE c.parent_id = item.id)`, seriesID)
}
