package api

import (
	"log/slog"
	"net/http"

	"lumiere-server/internal/jellyfin"
	"lumiere-server/internal/store"
)

// ContainerHandler is collections and playlists: making them, filling them,
// emptying them, deleting them.
//
// None of it existed. Every collection arrived from the import as an empty
// shell — Jellyfin keeps membership in its own table and the import never read
// it — and Add to Collection and Add to Playlist, on every right-click menu,
// answered 404. Membership now lives in the link table; the listing route
// reads it through the same `ParentId` the client already sends.
type ContainerHandler struct {
	Store *store.Store
	Items ItemsHandler
	Log   *slog.Logger
	// Where a collection's made-up poster is written. See refreshPoster.
	ImageDir string
}

// Create is POST /Collections and POST /Playlists. Jellyfin's contract: the
// name and the initial members arrive as query parameters, and the answer is
// the new id.
func (h ContainerHandler) Create(kind string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		get := caseInsensitive(r.URL.Query())
		name := get("Name")
		if name == "" {
			writeJSON(w, http.StatusBadRequest, errorBody{"a name is required"})
			return
		}
		id, err := h.Store.CreateContainer(kind, name, normalizeAll(splitList(get("Ids"))))
		if err != nil {
			h.Log.Error("container: could not create", "kind", kind, "error", err)
			writeJSON(w, http.StatusInternalServerError, errorBody{"could not create"})
			return
		}
		// A collection made from a suggestion knows its film series, so the
		// next suggestion pass adds to it rather than proposing it again.
		h.Store.SetItemValue(id, "tmdb_collection", get("TmdbCollectionId"))
		if kind == "BoxSet" {
			h.refreshPoster(id)
		}
		h.Log.Info("container: created", "kind", kind, "name", name, "id", id, "members", len(splitList(get("Ids"))))
		writeJSON(w, http.StatusOK, map[string]string{"Id": id})
	}
}

// Add is POST /Collections/{id}/Items and POST /Playlists/{id}/Items.
func (h ContainerHandler) Add(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	if id == "" || !h.Store.IsContainer(id) {
		writeJSON(w, http.StatusNotFound, errorBody{"no such collection or playlist"})
		return
	}
	ids := normalizeAll(splitList(caseInsensitive(r.URL.Query())("Ids")))
	if err := h.Store.AddLinks(id, ids); err != nil {
		h.Log.Error("container: could not add", "id", id, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not add"})
		return
	}
	h.refreshPoster(id)
	h.Log.Info("container: added", "id", id, "members", len(ids))
	w.WriteHeader(http.StatusNoContent)
}

// Remove is DELETE on the same paths. A playlist removes by `EntryIds`, a
// collection by `Ids`; an entry id here is the member's own id, since a member
// appears in a playlist once.
func (h ContainerHandler) Remove(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	if id == "" || !h.Store.IsContainer(id) {
		writeJSON(w, http.StatusNotFound, errorBody{"no such collection or playlist"})
		return
	}
	get := caseInsensitive(r.URL.Query())
	ids := normalizeAll(splitList(get("Ids")))
	if len(ids) == 0 {
		ids = normalizeAll(splitList(get("EntryIds")))
	}
	if err := h.Store.RemoveLinks(id, ids); err != nil {
		h.Log.Error("container: could not remove", "id", id, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not remove"})
		return
	}
	h.refreshPoster(id)
	h.Log.Info("container: removed", "id", id, "members", len(ids))
	w.WriteHeader(http.StatusNoContent)
}

// PlaylistItems is GET /Playlists/{id}/Items: the members in playlist order,
// each carrying its own id as PlaylistItemId so the client can remove it.
func (h ContainerHandler) PlaylistItems(w http.ResponseWriter, r *http.Request) {
	id := store.NormalizeID(r.PathValue("id"))
	q := queryFrom(r.URL.Query())
	q.ParentID = id
	q.Recursive = false
	items, total, err := h.Store.Items(q)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	wired := h.Items.wire(items)
	for i := range wired {
		wired[i].PlaylistItemId = wired[i].Id
	}
	writeJSON(w, http.StatusOK, jellyfin.ItemsResponse{
		Items: wired, TotalRecordCount: total, StartIndex: q.StartIndex,
	})
}

// DeleteItems is DELETE /Items?ids=: only a collection or a playlist may be
// deleted this way. This app never deletes media, and a request to do so is
// refused rather than honoured.
func (h ContainerHandler) DeleteItems(w http.ResponseWriter, r *http.Request) {
	ids := normalizeAll(splitList(caseInsensitive(r.URL.Query())("ids")))
	for _, id := range ids {
		if !h.Store.IsContainer(id) {
			writeJSON(w, http.StatusForbidden, errorBody{"only collections and playlists can be deleted"})
			return
		}
	}
	for _, id := range ids {
		if err := h.Store.DeleteContainer(id); err != nil {
			h.Log.Error("container: could not delete", "id", id, "error", err)
			writeJSON(w, http.StatusInternalServerError, errorBody{"could not delete"})
			return
		}
		h.Log.Info("container: deleted", "id", id)
	}
	w.WriteHeader(http.StatusNoContent)
}
