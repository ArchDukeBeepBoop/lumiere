package api

import (
	"time"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// logicalParent is what Jellyfin reports as an item's ParentId, which is not
// what its database holds.
//
// An episode's parent is its *season* and a season's is its *series*, whatever
// row physically contains them. Measured against a capture of Jellyfin's own
// answers: 67,946 Episode objects, every one with ParentId == SeasonId and not a
// single exception, and 5,026 Season objects with ParentId == SeriesId.
//
// Passing the stored parent through instead is invisible until it isn't. Lumiere
// lists a season's episodes by *parentId*, so an episode whose stored parent is
// the series folder rather than the season simply does not appear under it. On
// this library that is 1,928 of 2,026 episodes in one library and 574 in
// another: the rows sync, the counts match Jellyfin exactly, and the season page
// is empty anyway.

func logicalParent(it store.Item) string {
	switch it.Type {
	case "Episode":
		if it.SeasonID != "" {
			return it.SeasonID
		}
	case "Season":
		if it.SeriesID != "" {
			return it.SeriesID
		}
	}
	return it.ParentID
}

// ToWire turns a stored item into the object Lumiere decodes.
//
// The mapping is one function so that a list and a detail page cannot disagree
// about the same item — the client caches on Id, and two shapes for one id is
// how a field appears and disappears depending on where you opened it from.
func ToWire(it store.Item, serverID string) jellyfin.BaseItem {
	b := jellyfin.BaseItem{
		Id:                      it.ID,
		Name:                    it.Name,
		Type:                    it.Type,
		ServerId:                serverID,
		ParentId:                logicalParent(it),
		IsFolder:                it.IsFolder,
		SeriesId:                it.SeriesID,
		SeriesName:              it.SeriesName,
		SeasonId:                it.SeasonID,
		SeasonName:              it.SeasonName,
		IndexNumber:             it.IndexNumber,
		ParentIndexNumber:       it.ParentIndexNumber,
		OriginalTitle:           it.OriginalTitle,
		SortName:                it.SortName,
		Overview:                it.Overview,
		ExtraType:               it.ExtraType,
		ProductionYear:          it.ProductionYear,
		PremiereDate:            rfc3339(it.PremiereDate),
		DateCreated:             rfc3339(it.DateCreated),
		OfficialRating:          it.OfficialRating,
		CommunityRating:         it.CommunityRating,
		CriticRating:            it.CriticRating,
		RunTimeTicks:            it.RuntimeTicks,
		Container:               it.Container,
		Path:                    it.Path,
		CollectionType:          it.CollectionType,
		Genres:                  it.Genres,
		Tags:                    it.Tags,
		ImageTags:               it.Images,
		BackdropImageTags:       it.Backdrops,
		Album:                   it.Album,
		AlbumArtist:             it.AlbumArtist,
		Artists:                 it.Artists,
		ChildCount:              it.ChildCount,
		ProviderIds:             it.ProviderIDs,
		RecursiveItemCnt:        it.RecursiveItemCount,
		SeriesPrimaryImageTag:   it.SeriesPrimaryImageTag,
		ParentBackdropItemId:    it.ParentBackdropItemID,
		ParentBackdropImageTags: it.ParentBackdropTags,
		TopParentId:             LibraryView(it.LibraryID),
	}
	if it.Tagline != "" {
		// Taglines is a list on the wire and a column here: Jellyfin allows
		// several and nothing in this library has more than one.
		b.Taglines = []string{it.Tagline}
	}
	for _, s := range it.Studios {
		b.Studios = append(b.Studios, jellyfin.NamedItem{Id: s.ID, Name: s.Name})
	}
	// Emitted even when empty, because the capture shows all three on 100% of
	// items (§12.4) and a client that reads `ImageTags["Primary"]` without a nil
	// check should meet a map rather than nothing.
	if b.ImageTags == nil {
		b.ImageTags = map[string]string{}
	}
	if b.BackdropImageTags == nil {
		b.BackdropImageTags = []string{}
	}
	if b.Genres == nil {
		b.Genres = []string{}
	}

	b.UserData = wireUserData(it)
	return b
}

// wireUserData builds the UserData block, always.
//
// Always, even for an item nobody has touched: the capture shows it on 100% of
// items, and Lumiere reads Played and PlaybackPositionTicks without checking
// whether the block is there.
func wireUserData(it store.Item) *jellyfin.UserItemData {
	u := &jellyfin.UserItemData{
		ItemId: it.ID,
		// Jellyfin's Key is a provider-scoped string used to carry watch state
		// across re-identification. This server has no such concept, so the id
		// serves — Lumiere stores it and never interprets it.
		Key: it.ID,
	}
	if it.UserData == nil {
		return u
	}
	u.Played = it.UserData.Played
	u.PlayCount = it.UserData.PlayCount
	u.PlaybackPositionTicks = it.UserData.PositionTicks
	u.IsFavorite = it.UserData.IsFavorite
	u.UnplayedItemCount = it.UserData.UnplayedItemCount

	if stamp := rfc3339(it.UserData.LastPlayed); stamp != "" {
		// Absent rather than empty when nothing has been played, matching §12.5.
		// Continue Watching is ordered by this field, so emitting a zero value
		// for everything would silently reorder that shelf.
		u.LastPlayedDate = &stamp
	}
	if it.RuntimeTicks != nil && *it.RuntimeTicks > 0 && it.UserData.PositionTicks > 0 {
		pct := float64(it.UserData.PositionTicks) / float64(*it.RuntimeTicks) * 100
		u.PlayedPercentage = &pct
	}
	return u
}

// rfc3339 normalises Jellyfin's several timestamp shapes to one.
//
// Lumiere parses fractional seconds, whole seconds, and no timezone designator
// (§5.2). Emitting RFC-3339 with a Z means none of that variety has to be
// exercised, and a value this server cannot parse is dropped rather than sent
// as something the client will read as a different date.
func rfc3339(raw string) string {
	if raw == "" {
		return ""
	}
	for _, layout := range []string{
		time.RFC3339Nano, time.RFC3339,
		"2006-01-02 15:04:05.9999999", "2006-01-02 15:04:05",
		"2006-01-02T15:04:05.9999999", "2006-01-02",
	} {
		if t, err := time.Parse(layout, raw); err == nil {
			return t.UTC().Format(time.RFC3339)
		}
	}
	return ""
}
