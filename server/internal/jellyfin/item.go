// Package jellyfin holds the wire types: exactly the fields spec §5 says
// Lumiere decodes, and nothing else.
//
// The omissions are the point. Jellyfin's BaseItemDto has over a hundred keys
// and Lumiere reads about 45; the capture measured what the live server sends
// and §12.4 lists twelve fields emitted on every item and decoded by nobody,
// `ImageBlurHashes` chief among them. Across a 123-page sync those are the bulk
// of the bytes. Every field here earns its place by appearing in §5.2.
package jellyfin

// ItemsResponse is the envelope. All three keys appear on every page of the
// capture, and TotalRecordCount is what drives paging — a wrong value here does
// not cause an error, it silently truncates the library.
type ItemsResponse struct {
	Items            []BaseItem `json:"Items"`
	TotalRecordCount int        `json:"TotalRecordCount"`
	StartIndex       int        `json:"StartIndex"`
}

// BaseItem is one row in any list.
//
// Optional numbers are pointers so that "absent" and "zero" stay different: a
// season 0 is Specials, an IndexNumber of 0 is a legitimate episode, and
// omitempty on a plain int would erase both.
type BaseItem struct {
	Id string `json:"Id"`
	// PlaylistItemId is set only on a playlist listing: the handle the client
	// removes an entry by.
	PlaylistItemId string `json:"PlaylistItemId,omitempty"`
	Name           string `json:"Name"`
	Type           string `json:"Type"`
	ServerId       string `json:"ServerId,omitempty"`

	ParentId string `json:"ParentId,omitempty"`
	IsFolder bool   `json:"IsFolder"`

	SeriesId          string `json:"SeriesId,omitempty"`
	SeriesName        string `json:"SeriesName,omitempty"`
	SeasonId          string `json:"SeasonId,omitempty"`
	SeasonName        string `json:"SeasonName,omitempty"`
	IndexNumber       *int   `json:"IndexNumber,omitempty"`
	ParentIndexNumber *int   `json:"ParentIndexNumber,omitempty"`

	OriginalTitle    string            `json:"OriginalTitle,omitempty"`
	SortName         string            `json:"SortName,omitempty"`
	Overview         string            `json:"Overview,omitempty"`
	Taglines         []string          `json:"Taglines,omitempty"`
	ExtraType        string            `json:"ExtraType,omitempty"`
	ProductionYear   *int              `json:"ProductionYear,omitempty"`
	PremiereDate     string            `json:"PremiereDate,omitempty"`
	DateCreated      string            `json:"DateCreated,omitempty"`
	OfficialRating   string            `json:"OfficialRating,omitempty"`
	CommunityRating  *float64          `json:"CommunityRating,omitempty"`
	CriticRating     *float64          `json:"CriticRating,omitempty"`
	RunTimeTicks     *int64            `json:"RunTimeTicks,omitempty"`
	Container        string            `json:"Container,omitempty"`
	Path             string            `json:"Path,omitempty"`
	CollectionType   string            `json:"CollectionType,omitempty"`
	ChildCount       *int              `json:"ChildCount,omitempty"`
	ProviderIds      map[string]string `json:"ProviderIds,omitempty"`
	RecursiveItemCnt *int              `json:"RecursiveItemCount,omitempty"`

	Genres  []string    `json:"Genres"`
	Tags    []string    `json:"Tags,omitempty"`
	Studios []NamedItem `json:"Studios,omitempty"`
	People  []Person    `json:"People,omitempty"`

	// ImageTags' value is a cache key, not a filename: the client caches on it
	// forever and only refetches when it changes (§7.1).
	ImageTags               map[string]string `json:"ImageTags"`
	BackdropImageTags       []string          `json:"BackdropImageTags"`
	ParentBackdropItemId    string            `json:"ParentBackdropItemId,omitempty"`
	ParentBackdropImageTags []string          `json:"ParentBackdropImageTags,omitempty"`
	SeriesPrimaryImageTag   string            `json:"SeriesPrimaryImageTag,omitempty"`

	Album       string   `json:"Album,omitempty"`
	AlbumId     string   `json:"AlbumId,omitempty"`
	AlbumArtist string   `json:"AlbumArtist,omitempty"`
	Artists     []string `json:"Artists,omitempty"`

	// Detail only: the list field set never asks for these, and no item in any
	// list response in the capture carried MediaSources.
	MediaSources []MediaSource `json:"MediaSources,omitempty"`
	MediaStreams []MediaStream `json:"MediaStreams,omitempty"`
	Chapters     []Chapter     `json:"Chapters,omitempty"`
	// Scrubbing previews, keyed by media source then width. See media.MakeTrickplay.
	Trickplay any `json:"Trickplay,omitempty"`
	// The library (as the client's UserViews names it) the item is in, so a
	// client without a local catalogue can keep private libraries out of
	// Continue Watching and search.
	TopParentId string `json:"TopParentId,omitempty"`

	UserData *UserItemData `json:"UserData,omitempty"`
}

type NamedItem struct {
	Id   string `json:"Id"`
	Name string `json:"Name"`
}

type Person struct {
	Id              string `json:"Id"`
	Name            string `json:"Name"`
	Role            string `json:"Role,omitempty"`
	Type            string `json:"Type,omitempty"`
	PrimaryImageTag string `json:"PrimaryImageTag,omitempty"`
}

// UserItemData carries watch state.
//
// LastPlayedDate and PlayedPercentage are pointers because the live server omits
// them rather than sending null (§12.5), and Continue Watching is ordered by
// LastPlayedDate — a server that always emits it, even empty, reorders that
// shelf without erroring.
type UserItemData struct {
	ItemId                string   `json:"ItemId"`
	Key                   string   `json:"Key"`
	Played                bool     `json:"Played"`
	PlayCount             int      `json:"PlayCount"`
	PlaybackPositionTicks int64    `json:"PlaybackPositionTicks"`
	IsFavorite            bool     `json:"IsFavorite"`
	LastPlayedDate        *string  `json:"LastPlayedDate,omitempty"`
	PlayedPercentage      *float64 `json:"PlayedPercentage,omitempty"`
	UnplayedItemCount     *int     `json:"UnplayedItemCount,omitempty"`
}
