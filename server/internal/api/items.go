package api

import (
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// ItemsHandler serves the library read path — the workhorse of spec §4.2.
type ItemsHandler struct {
	Store    *store.Store
	Identity Identity
	Log      *slog.Logger
}

// Items is GET /Items.
func (h ItemsHandler) Items(w http.ResponseWriter, r *http.Request) {
	q := queryFrom(r.URL.Query())
	items, total, err := h.Store.Items(q)
	if err != nil {
		h.Log.Error("items query failed", "error", err, "query", r.URL.RawQuery)
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items:            h.wire(items),
		TotalRecordCount: total,
		StartIndex:       q.StartIndex,
	})
}

// queryFrom parses the query string into a store.Query.
//
// Jellyfin's parameter names are inconsistently cased across its own clients, so
// every lookup is case-insensitive: Lumiere sends `userId` and `SortBy` in the
// same URL, and a server that matched exactly would work for one and not the
// other.
func queryFrom(v url.Values) store.Query {
	get := caseInsensitive(v)

	q := store.Query{
		ParentID:   store.NormalizeID(get("ParentId")),
		Recursive:  strings.EqualFold(get("Recursive"), "true"),
		SearchTerm: strings.TrimSpace(get("SearchTerm")),
		NameFrom:   strings.TrimSpace(get("NameStartsWithOrGreater")),
		StartIndex: atoiOr(get("StartIndex"), 0),
		Limit:      atoiOr(get("Limit"), 0),
		Descending: strings.EqualFold(get("SortOrder"), "Descending"),
		// Extras are hidden from every shelf by the client, and counting them
		// would make TotalRecordCount disagree with what is shown — which is the
		// number paging is driven by.
		ExcludeExtras: true,
	}
	q.Types = splitList(get("IncludeItemTypes"))
	q.SortBy = splitList(get("SortBy"))
	q.Filters = splitList(get("Filters"))
	q.PersonIDs = normalizeAll(splitList(get("PersonIds")))
	// Three names for one question in Jellyfin's API; answered the same way.
	for _, key := range []string{"ArtistIds", "AlbumArtistIds", "ContributingArtistIds"} {
		q.ArtistIDs = append(q.ArtistIDs, normalizeAll(splitList(get(key)))...)
	}
	q.IDs = normalizeAll(splitList(get("Ids")))
	// Pipe-separated, alone among the list parameters, because genre names
	// contain commas. Jellyfin's inconsistency, and it has to be matched exactly.
	q.Genres = splitOn(get("Genres"), "|")
	for _, y := range splitList(get("Years")) {
		if n, err := strconv.Atoi(y); err == nil {
			q.Years = append(q.Years, n)
		}
	}
	return q
}

// caseInsensitive returns a lookup that ignores parameter-name casing.
func caseInsensitive(v url.Values) func(string) string {
	lower := make(map[string]string, len(v))
	for k, vals := range v {
		if len(vals) > 0 {
			lower[strings.ToLower(k)] = vals[0]
		}
	}
	return func(key string) string { return lower[strings.ToLower(key)] }
}

func splitList(s string) []string { return splitOn(s, ",") }

func splitOn(s, sep string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	var out []string
	for _, part := range strings.Split(s, sep) {
		if p := strings.TrimSpace(part); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func normalizeAll(ids []string) []string {
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		if n := store.NormalizeID(id); n != "" {
			out = append(out, n)
		}
	}
	return out
}

// equalFoldASCII is strings.EqualFold, named at the call sites so a
// case-insensitive comparison reads as a decision rather than an accident.
func equalFoldASCII(a, b string) bool { return strings.EqualFold(a, b) }

func itoa(n int) string { return strconv.Itoa(n) }

func atoiOr(s string, fallback int) int {
	if n, err := strconv.Atoi(strings.TrimSpace(s)); err == nil {
		return n
	}
	return fallback
}

func (h ItemsHandler) wire(items []store.Item) []jellyfin.BaseItem {
	// Never nil: `"Items": null` decodes as an empty list in some clients and as
	// a failure in others, and an empty page is a normal answer.
	out := make([]jellyfin.BaseItem, 0, len(items))
	for _, it := range items {
		out = append(out, ToWire(it, h.Identity.ServerID))
	}
	return out
}
