package store

import (
	"database/sql"
	"errors"
	"strings"
)

// Item is one row as stored. The API package turns it into a wire object; this
// package does not know what JSON looks like.
type Item struct {
	ID, Type, Name                    string
	SortName, OriginalTitle, Overview string
	Tagline                           string
	ParentID, LibraryID               string
	SeriesID, SeriesName              string
	SeasonID, SeasonName              string
	IndexNumber, ParentIndexNumber    *int
	ProductionYear                    *int
	PremiereDate, DateCreated         string
	OfficialRating                    string
	CommunityRating, CriticRating     *float64
	RuntimeTicks                      *int64
	Container, Path                   string
	Size                              int64
	TotalBitrate                      int
	IsFolder                          bool
	ExtraType, Album, CollectionType  string
	AlbumArtist                       string
	Artists                           []string

	// Hydrated separately, one query per page rather than per row.
	Genres, Tags []string
	ProviderIDs  map[string]string
	Studios      []Named
	Images       map[string]string
	Backdrops    []string

	// Counts shown on cards, for the containers that have children.
	ChildCount, RecursiveItemCount *int

	// The remembered per-item track choices, from user_data.
	AudioIndex, SubtitleIndex *int

	// Artwork inherited from the series, for episodes that have none of their
	// own — which is nearly all of them.
	SeriesPrimaryImageTag string
	ParentBackdropItemID  string
	ParentBackdropTags    []string
	UserData              *UserData
}

type Named struct{ ID, Name string }

type UserData struct {
	Played            bool
	PlayCount         int
	PositionTicks     int64
	IsFavorite        bool
	LastPlayed        string
	UnplayedItemCount *int
}

// Items runs a query and returns one page plus the total.
//
// Two round trips, not two hundred: the page is read, then genres, images and
// watch state are fetched for that page's ids in one statement each. The
// alternative — a join, or a lookup per row — either multiplies rows by genre
// count or issues 200 queries per page across a 123-page sync.
func (s *Store) Items(q Query) ([]Item, int, error) {
	// Resolved for flat listings too, not only recursive ones. A library view's
	// children carry the *physical* folder as their parent, so asking for the
	// view's direct children matched nothing at all — which is why a music
	// library's Folders tab came back empty while every other tab had 2,301
	// tracks to show.
	if q.ParentID != "" {
		folders, err := s.resolveFolders(q.ParentID)
		if err != nil {
			return nil, 0, err
		}
		q.FolderIDs = folders
	}
	where, args := q.where()

	var total int
	if err := s.DB.QueryRow(`SELECT count(*) FROM item i`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	limitSQL, limitArgs := q.limitClause()
	rows, err := s.DB.Query(
		`SELECT`+itemColumns+` FROM item i`+where+q.orderBy()+limitSQL,
		append(args, limitArgs...)...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var out []Item
	for rows.Next() {
		it, err := scanItem(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, it)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	if err := s.hydrate(out); err != nil {
		return nil, 0, err
	}
	return out, total, nil
}

// ItemByID is the single-item read, sharing the same projection and hydration
// so a detail page cannot disagree with the list it was opened from.
func (s *Store) ItemByID(id string) (Item, error) {
	rows, err := s.DB.Query(`SELECT`+itemColumns+` FROM item i WHERE i.id = ?`, id)
	if err != nil {
		return Item{}, err
	}
	defer rows.Close()
	if !rows.Next() {
		return Item{}, ErrNoItem
	}
	it, err := scanItem(rows)
	if err != nil {
		return Item{}, err
	}
	one := []Item{it}
	if err := s.hydrate(one); err != nil {
		return Item{}, err
	}
	return one[0], nil
}

func scanItem(rows *sql.Rows) (Item, error) {
	var it Item
	var sortName, originalTitle, overview, tagline sql.NullString
	var parentID, libraryID, seriesID, seriesName sql.NullString
	var seasonID, seasonName sql.NullString
	var indexNumber, parentIndex, productionYear sql.NullInt64
	var premiereDate, dateCreated, officialRating sql.NullString
	var communityRating, criticRating sql.NullFloat64
	var runtimeTicks sql.NullInt64
	var container, path sql.NullString
	var isFolder sql.NullBool
	var extraType, album, collectionType sql.NullString
	var albumArtist, artists sql.NullString
	var size sql.NullInt64
	var totalBitrate sql.NullInt64

	if err := rows.Scan(&it.ID, &it.Type, &it.Name, &sortName, &originalTitle,
		&overview, &tagline, &parentID, &libraryID, &seriesID, &seriesName,
		&seasonID, &seasonName, &indexNumber, &parentIndex, &productionYear,
		&premiereDate, &dateCreated, &officialRating, &communityRating,
		&criticRating, &runtimeTicks, &container, &path, &isFolder,
		&extraType, &album, &albumArtist, &artists,
		&collectionType, &size, &totalBitrate); err != nil {
		return Item{}, err
	}

	it.SortName, it.OriginalTitle = sortName.String, originalTitle.String
	it.Overview, it.Tagline = overview.String, tagline.String
	it.ParentID, it.LibraryID = parentID.String, libraryID.String
	it.SeriesID, it.SeriesName = seriesID.String, seriesName.String
	it.SeasonID, it.SeasonName = seasonID.String, seasonName.String
	it.IndexNumber = intPtr(indexNumber)
	it.ParentIndexNumber = intPtr(parentIndex)
	it.ProductionYear = intPtr(productionYear)
	it.PremiereDate, it.DateCreated = premiereDate.String, dateCreated.String
	it.OfficialRating = officialRating.String
	if communityRating.Valid {
		it.CommunityRating = &communityRating.Float64
	}
	if criticRating.Valid {
		it.CriticRating = &criticRating.Float64
	}
	if runtimeTicks.Valid {
		it.RuntimeTicks = &runtimeTicks.Int64
	}
	it.Container, it.Path = container.String, path.String
	it.IsFolder = isFolder.Bool
	it.ExtraType, it.Album = extraType.String, album.String
	it.AlbumArtist = albumArtist.String
	it.Artists = splitArtists(artists.String)
	it.CollectionType = collectionType.String
	it.Size = size.Int64
	it.TotalBitrate = int(totalBitrate.Int64)
	return it, nil
}

func intPtr(n sql.NullInt64) *int {
	if !n.Valid {
		return nil
	}
	v := int(n.Int64)
	return &v
}

func idList(items []Item) (string, []any) {
	args := make([]any, len(items))
	for i, it := range items {
		args[i] = it.ID
	}
	return placeholders(len(items)), args
}

func indexOf(items []Item) map[string]*Item {
	m := make(map[string]*Item, len(items))
	for i := range items {
		m[items[i].ID] = &items[i]
	}
	return m
}

// LibraryFolders is resolveFolders for callers outside this file: the physical
// folder ids backing a library view.
func (s *Store) LibraryFolders(viewID string) ([]string, error) {
	return s.resolveFolders(viewID)
}

// resolveFolders maps a library view id to the physical folder ids its
// contents are filed under. Empty for anything that is not a library view,
// which is the common case and costs one indexed lookup.
func (s *Store) resolveFolders(viewID string) ([]string, error) {
	rows, err := s.DB.Query(
		`SELECT folder_id FROM library_folder WHERE view_id = ?`, viewID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// ImageRef is what the image endpoint needs to serve one picture.
type ImageRef struct {
	Path  string
	Tag   string
	Width int
}

// Image finds one image by item, kind and index.
//
// Returns sql.ErrNoRows' stand-in when there is none, which the handler turns
// into a 404 — the client renders a placeholder and carries on, so a missing
// picture must never be an error page.
func (s *Store) Image(itemID, kind string, idx int) (ImageRef, error) {
	var ref ImageRef
	var width sql.NullInt64
	err := s.DB.QueryRow(
		`SELECT path, tag, width FROM image
		 WHERE item_id = ? AND kind = ? AND idx = ?`, itemID, kind, idx,
	).Scan(&ref.Path, &ref.Tag, &width)
	if errors.Is(err, sql.ErrNoRows) {
		return ImageRef{}, ErrNoImage
	}
	ref.Width = int(width.Int64)
	return ref, err
}

// splitArtists unpacks the pipe-separated list Jellyfin stores.
//
// Empty segments are dropped: a trailing separator is common in that data and
// would otherwise become an artist with no name, drawn as a gap in the row.
func splitArtists(joined string) []string {
	if joined == "" {
		return nil
	}
	var out []string
	for _, name := range strings.Split(joined, "|") {
		if trimmed := strings.TrimSpace(name); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}
