package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"lumiere-server/internal/store"
)

// LibrariesHandler is where libraries are made and their folders chosen —
// the first-run guide and the Libraries settings page on every app. Each
// change starts a scan, so what was added shows up without a second step.
type LibrariesHandler struct {
	Store   *store.Store
	Refresh *RefreshHandler
	Log     *slog.Logger
}

// Register adds the routes.
func (h LibrariesHandler) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /Lumiere/Libraries", h.List)
	mux.HandleFunc("POST /Lumiere/Libraries", h.Create)
	mux.HandleFunc("POST /Lumiere/Libraries/{id}", h.Update)
	mux.HandleFunc("DELETE /Lumiere/Libraries/{id}", h.Remove)
	mux.HandleFunc("POST /Lumiere/Libraries/{id}/Folders", h.AddFolder)
	mux.HandleFunc("DELETE /Lumiere/Libraries/{id}/Folders/{folder}", h.RemoveFolder)
	mux.HandleFunc("GET /Lumiere/Browse", h.Browse)
}

// List is GET /Lumiere/Libraries.
func (h LibrariesHandler) List(w http.ResponseWriter, r *http.Request) {
	libs, err := h.Store.ListLibraries()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorBody{"query failed"})
		return
	}
	if libs == nil {
		libs = []store.Library{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"Libraries": libs})
}

type libraryRequest struct {
	Name           string
	CollectionType *string
	Paths          []string
	Path           string
}

func decodeLibrary(w http.ResponseWriter, r *http.Request) (libraryRequest, bool) {
	var req libraryRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"invalid request body"})
		return req, false
	}
	return req, true
}

// Create is POST /Lumiere/Libraries {"Name", "CollectionType", "Paths"}.
func (h LibrariesHandler) Create(w http.ResponseWriter, r *http.Request) {
	req, ok := decodeLibrary(w, r)
	if !ok {
		return
	}
	for _, p := range req.Paths {
		if !isDir(p) {
			writeJSON(w, http.StatusBadRequest, errorBody{"not a folder: " + p})
			return
		}
	}
	kind := ""
	if req.CollectionType != nil {
		kind = *req.CollectionType
	}
	id, err := h.Store.CreateLibrary(req.Name, kind, req.Paths)
	if h.failed(w, err) {
		return
	}
	h.Log.Info("library created", "name", req.Name, "kind", kind, "folders", len(req.Paths))
	h.rescan()
	writeJSON(w, http.StatusOK, map[string]string{"Id": id})
}

// Update is POST /Lumiere/Libraries/{id} {"Name"?, "CollectionType"?}.
func (h LibrariesHandler) Update(w http.ResponseWriter, r *http.Request) {
	req, ok := decodeLibrary(w, r)
	if !ok || h.failed(w, h.Store.UpdateLibrary(r.PathValue("id"), req.Name, req.CollectionType)) {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Remove is DELETE /Lumiere/Libraries/{id}. Files on disk are never touched.
func (h LibrariesHandler) Remove(w http.ResponseWriter, r *http.Request) {
	if h.failed(w, h.Store.RemoveLibrary(r.PathValue("id"))) {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// AddFolder is POST /Lumiere/Libraries/{id}/Folders {"Path"}.
func (h LibrariesHandler) AddFolder(w http.ResponseWriter, r *http.Request) {
	req, ok := decodeLibrary(w, r)
	if !ok {
		return
	}
	if !isDir(req.Path) {
		writeJSON(w, http.StatusBadRequest, errorBody{"not a folder: " + req.Path})
		return
	}
	if h.failed(w, h.Store.AddLibraryFolder(r.PathValue("id"), req.Path)) {
		return
	}
	h.rescan()
	w.WriteHeader(http.StatusNoContent)
}

// RemoveFolder is DELETE /Lumiere/Libraries/{id}/Folders/{folder}.
func (h LibrariesHandler) RemoveFolder(w http.ResponseWriter, r *http.Request) {
	if h.failed(w, h.Store.RemoveLibraryFolder(r.PathValue("id"), r.PathValue("folder"))) {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h LibrariesHandler) failed(w http.ResponseWriter, err error) bool {
	switch {
	case err == nil:
		return false
	case errors.Is(err, store.ErrNoItem):
		writeJSON(w, http.StatusNotFound, errorBody{"no such library or folder"})
	case errors.Is(err, store.ErrBadLibrary):
		writeJSON(w, http.StatusBadRequest, errorBody{"a name, a known kind, and folders not already in a library"})
	default:
		h.Log.Error("library change failed", "error", err)
		writeJSON(w, http.StatusInternalServerError, errorBody{"could not save"})
	}
	return true
}

func (h LibrariesHandler) rescan() {
	if h.Refresh != nil {
		if err := h.Refresh.StartScan(); err != nil {
			h.Log.Info("scan after library change", "error", err)
		}
	}
}

func isDir(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir() && filepath.IsAbs(path)
}

// BrowseEntry is one folder in a listing.
type BrowseEntry struct {
	Name string `json:"Name"`
	Path string `json:"Path"`
}

// Browse is GET /Lumiere/Browse?path=… — the folders inside one, for apps
// that cannot open a picker on the server's disk (the phone and the TV).
// With no path it lists the places media usually lives.
func (h LibrariesHandler) Browse(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Query().Get("path")
	out := map[string]any{"Path": path, "Parent": ""}
	var entries []BrowseEntry
	if path == "" {
		home, _ := os.UserHomeDir()
		for _, p := range []string{home, filepath.Join(home, "Movies"), filepath.Join(home, "Music"), "/Volumes", "/media", "/mnt"} {
			if isDir(p) {
				entries = append(entries, BrowseEntry{Name: p, Path: p})
			}
		}
	} else {
		if !isDir(path) {
			writeJSON(w, http.StatusBadRequest, errorBody{"not a folder"})
			return
		}
		out["Parent"] = filepath.Dir(path)
		list, _ := os.ReadDir(path)
		for _, e := range list {
			full := filepath.Join(path, e.Name())
			if strings.HasPrefix(e.Name(), ".") || !isDir(full) {
				continue
			}
			entries = append(entries, BrowseEntry{Name: e.Name(), Path: full})
		}
		sort.Slice(entries, func(i, j int) bool {
			return strings.ToLower(entries[i].Name) < strings.ToLower(entries[j].Name)
		})
	}
	if entries == nil {
		entries = []BrowseEntry{}
	}
	out["Folders"] = entries
	writeJSON(w, http.StatusOK, out)
}
