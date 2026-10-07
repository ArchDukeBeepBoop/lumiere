package store

// sortColumns is the allowlist. A SortBy value that is not here is dropped
// rather than interpolated — this is the one place a request string could
// otherwise reach the SQL text.
var sortColumns = map[string]string{
	"sortname":        "i.sort_name COLLATE NOCASE, i.name COLLATE NOCASE",
	"name":            "i.name COLLATE NOCASE",
	"datecreated":     "i.date_created",
	"premieredate":    "i.premiere_date",
	"productionyear":  "i.production_year",
	"communityrating": "i.community_rating",
	"random":          "RANDOM()",
	"indexnumber":     "i.parent_index_number, i.index_number",
	"dateplayed":      "(SELECT u.last_played FROM user_data u WHERE u.item_id = i.id)",
	// The Tracks tab's columns. Missing, they were dropped and every one of
	// them sorted by name.
	"albumartist":       "COALESCE(NULLIF(i.album_artist, ''), i.artists) COLLATE NOCASE",
	"artist":            "i.artists COLLATE NOCASE",
	"album":             "i.album COLLATE NOCASE",
	"parentindexnumber": "i.parent_index_number",
	"runtime":           "i.runtime_ticks",
	"playcount":         "(SELECT u.play_count FROM user_data u WHERE u.item_id = i.id)",
}
