package metadata

import (
	"context"
	"database/sql"
	"log/slog"
	"time"

	"lumiere-server/internal/store"
)

// Enricher names what the scanner found.
//
// Works on the items that have nothing: a series or film with no overview and
// no artwork, which is exactly what a filesystem scan produces. Anything
// Jellyfin already described is left alone — the import's answer is not
// improved by a second opinion, and overwriting it would discard hand
// corrections.
type Enricher struct {
	Store    *store.Store
	TMDB     *TMDB
	ImageDir string
	Log      *slog.Logger
}

// Pending is one item waiting to be named.
type Pending struct {
	ID    string
	Type  string
	Name  string
	Year  int
	Genre string
	// TmdbID is set only by PendingCredits, for a title already matched.
	TmdbID string
}

// PendingClause is the condition for "worth looking up", used by the query
// that does the work and by the count that reports it. Shared because the two
// have already drifted apart once: the card said 26 and the pass did 200.
//
// The folder libraries are excluded, and that is the point of the clause rather
// than a filter bolted on. `3D` and `My Videos` hold loose clips — a file named
// after the site it came from is not a title any provider has ever heard of, so
// 1,900 of them were queued for a lookup that could only ever miss. A library
// with no collection type is one Jellyfin could not identify either; that is
// precisely what those two are.
const PendingClause = `
	type IN ('Series', 'Movie')
	AND (
		COALESCE(overview, '') = ''
		OR NOT EXISTS (
		  SELECT 1 FROM image g WHERE g.item_id = item.id AND g.kind = 'Primary'
		)
	)
	AND NOT EXISTS (
		SELECT 1 FROM item_value v
		WHERE v.item_id = item.id AND v.kind LIKE 'provider:%'
	)
	AND EXISTS (
		SELECT 1 FROM library_folder lf
		JOIN item view ON view.id = lf.view_id
		WHERE lf.folder_id = item.library_id
		  AND COALESCE(view.collection_type, '') <> ''
	)
	AND NOT EXISTS ( -- libraries kept off the movie database; see store.MetaLookupSkipped
		SELECT 1 FROM library_folder lf, meta m
		WHERE m.key = 'metadata_skip_libraries' AND lf.folder_id = item.library_id
		  AND instr(',' || m.value || ',', ',' || lf.view_id || ',') > 0
	)`

// PendingItems lists what has no metadata yet.
//
// Series and films only. An episode's own title is a per-episode lookup and a
// different piece of work; naming the show is what makes a library legible.
func (e *Enricher) PendingItems(limit int) ([]Pending, error) {
	rows, err := e.Store.DB.Query(`
		SELECT id, type, name, COALESCE(production_year, 0)
		FROM item
		WHERE `+PendingClause+`
		ORDER BY date_created DESC
		LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var pending []Pending
	for rows.Next() {
		var item Pending
		if err := rows.Scan(&item.ID, &item.Type, &item.Name, &item.Year); err != nil {
			return nil, err
		}
		pending = append(pending, item)
	}
	return pending, rows.Err()
}

// Enrich names one item.
//
// Returns whether anything was written. A miss is ordinary — a folder named
// after a scene group matches nothing, and that is not a failure to report.
func (e *Enricher) Enrich(ctx context.Context, item Pending) (bool, error) {
	isSeries := item.Type == "Series"

	candidates, err := e.search(ctx, isSeries, item)
	if err != nil {
		return false, err
	}

	best, ok := Best(item.Name, item.Year, candidates)
	if !ok {
		// The other kind, before giving up. A scan files a folder holding one
		// film as a series often enough to matter — "London Has Fallen" sat
		// here as a show with no artwork, because a search for a *series* of
		// that name finds nothing and there was nowhere else to look.
		if other, err := e.search(ctx, !isSeries, item); err == nil {
			if match, found := Best(item.Name, item.Year, other); found {
				best, ok, isSeries = match, true, !isSeries
			}
		}
	}
	if !ok {
		// Recorded as asked-and-missed, so the next pass does not spend a
		// request asking the same question again.
		return false, e.markMissed(item.ID)
	}

	var details Details
	if isSeries {
		details, err = e.TMDB.Series(ctx, best.ID)
	} else {
		details, err = e.TMDB.Movie(ctx, best.ID)
	}
	if err != nil {
		return false, err
	}

	if err := e.apply(item, details); err != nil {
		return false, err
	}
	if details.PosterPath != "" {
		// Best-effort, and after the text: a title named without its poster is
		// a success with a gap, and failing the whole thing would undo the
		// naming that already worked.
		if err := e.fetchImage(item.ID, "Primary", "w780"+details.PosterPath); err != nil {
			e.Log.Info("metadata: poster not fetched", "item", item.Name, "reason", err)
		}
	}
	if details.BackdropPath != "" {
		if err := e.fetchImage(item.ID, "Backdrop", "w1280"+details.BackdropPath); err != nil {
			e.Log.Info("metadata: backdrop not fetched", "item", item.Name, "reason", err)
		}
	}
	// And the people, from the same match. Best-effort like the pictures.
	item.TmdbID = details.ID
	if _, err := e.Credit(ctx, item, isSeries); err != nil {
		e.Log.Info("metadata: credits not fetched", "item", item.Name, "reason", err)
	}
	return true, nil
}

// search asks one kind.
func (e *Enricher) search(ctx context.Context, series bool, item Pending) ([]Candidate, error) {
	if series {
		return e.TMDB.SearchSeries(ctx, item.Name, item.Year)
	}
	return e.TMDB.SearchMovie(ctx, item.Name, item.Year)
}

// apply writes the text in one transaction.
//
// The name is *not* overwritten. The folder is what the owner called it, and a
// provider's preferred spelling — "Dr. STONE" over "Dr Stone" — is not worth
// renaming somebody's library for. What is written is what the library did not
// have: the synopsis, the year, the rating, the genres, and the id that says
// which title this is.
func (e *Enricher) apply(item Pending, details Details) error {
	tx, err := e.Store.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.Exec(`
		UPDATE item SET
			overview = COALESCE(NULLIF(overview, ''), ?),
			production_year = COALESCE(production_year, ?),
			community_rating = COALESCE(community_rating, ?)
		WHERE id = ?`,
		nullString(details.Overview), nullYear(details.Year),
		nullRating(details.Rating), item.ID,
	); err != nil {
		return err
	}

	for _, genre := range details.Genres {
		if _, err := tx.Exec(`
			INSERT INTO item_value (item_id, kind, value) VALUES (?, 'genre', ?)
			ON CONFLICT DO NOTHING`, item.ID, genre); err != nil {
			return err
		}
	}
	for _, studio := range details.Studios {
		if _, err := tx.Exec(`
			INSERT INTO item_value (item_id, kind, value) VALUES (?, 'studio', ?)
			ON CONFLICT DO NOTHING`, item.ID, studio); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(`
		INSERT INTO item_value (item_id, kind, value) VALUES (?, 'provider:Tmdb', ?)
		ON CONFLICT DO NOTHING`, item.ID, details.ID); err != nil {
		return err
	}
	// The film series, which is what makes collections. Only the Jellyfin
	// import ever wrote this, so a film named here joined no series.
	if details.CollectionID != "" {
		if _, err := tx.Exec(`
			INSERT INTO item_value (item_id, kind, value) VALUES (?, 'provider:TmdbCollection', ?)
			ON CONFLICT DO NOTHING`, item.ID, details.CollectionID); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// markMissed records that this item was asked about and matched nothing.
//
// Under the same `provider:` namespace with an empty-shaped value, so
// `PendingItems` skips it. Without this, every pass spends its whole budget
// re-asking about the same unmatchable folders and never reaches the rest.
func (e *Enricher) markMissed(itemID string) error {
	_, err := e.Store.DB.Exec(`
		INSERT INTO item_value (item_id, kind, value) VALUES (?, 'provider:none', ?)
		ON CONFLICT DO NOTHING`, itemID, time.Now().UTC().Format(time.RFC3339))
	return err
}

func nullString(value string) any {
	if value == "" {
		return nil
	}
	return value
}

func nullYear(year int) any {
	if year <= 0 {
		return nil
	}
	return year
}

func nullRating(rating float64) any {
	if rating <= 0 {
		return nil
	}
	return rating
}

var _ = sql.ErrNoRows
