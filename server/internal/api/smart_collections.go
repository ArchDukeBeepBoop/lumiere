package api

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	"lumiere-server/internal/store"
)

// Smart collections over HTTP, and the refresher that keeps them current.
// See store/smart.go for what a rule can say.

type smartBody struct {
	Id    string           `json:"Id,omitempty"`
	Name  string           `json:"Name"`
	Rules store.SmartRules `json:"Rules"`
}

// privateFolders are the folders of private libraries, which a smart
// collection leaves out unless a rule names one.
func (h CollectionSuggestHandler) privateFolders() []string {
	rooms := h.Store.LibraryRooms(h.privateViews())
	var out []string
	for folder, private := range rooms.Private {
		if private {
			out = append(out, folder)
		}
	}
	return out
}

// SmartList is GET /Lumiere/SmartCollections.
func (h CollectionSuggestHandler) SmartList(w http.ResponseWriter, r *http.Request) {
	type entry struct {
		Id, Name string
		Rules    store.SmartRules
		Count    int
	}
	var out []entry
	for id, rules := range h.Store.SmartCollections() {
		var name string
		var count int
		h.Store.DB.QueryRow(`SELECT name FROM item WHERE id = ?`, id).Scan(&name)
		h.Store.DB.QueryRow(`SELECT count(*) FROM link WHERE parent_id = ?`, id).Scan(&count)
		out = append(out, entry{id, name, rules, count})
	}
	writeJSON(w, http.StatusOK, map[string]any{"Items": out})
}

// SmartPreview is POST /Lumiere/SmartCollections/Preview {"Rules": …}: how
// many titles the rules match now, and the first few, while they are edited.
func (h CollectionSuggestHandler) SmartPreview(w http.ResponseWriter, r *http.Request) {
	var body smartBody
	if err := json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	members, err := h.Store.SmartMembers(body.Rules, h.privateFolders())
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{err.Error()})
		return
	}
	var names []string
	for _, id := range members[:min(12, len(members))] {
		var n string
		h.Store.DB.QueryRow(`SELECT name FROM item WHERE id = ?`, id).Scan(&n)
		names = append(names, n)
	}
	writeJSON(w, http.StatusOK, map[string]any{"Count": len(members), "Names": names})
}

// SmartSave is POST /Lumiere/SmartCollections: create, or with an Id update,
// a smart collection; its members are filled at once.
func (h CollectionSuggestHandler) SmartSave(w http.ResponseWriter, r *http.Request) {
	var body smartBody
	if err := json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	body.Name = strings.TrimSpace(body.Name)
	if body.Name == "" {
		writeJSON(w, http.StatusBadRequest, errorBody{"a smart collection needs a name"})
		return
	}
	members, err := h.Store.SmartMembers(body.Rules, h.privateFolders())
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{err.Error()})
		return
	}
	raw, _ := json.Marshal(body.Rules)
	id := body.Id
	if id == "" {
		id, err = h.Store.CreateCollectionIn(body.Name, h.smartRoom(body.Rules), members)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, errorBody{"could not create"})
			return
		}
	} else {
		h.Store.DB.Exec(`UPDATE item SET name = ?, sort_name = ? WHERE id = ? AND type = 'BoxSet'`, body.Name, body.Name, id)
		h.Store.SyncLinks(id, members)
	}
	h.Store.SetLinkOrder(id, members)
	h.Store.SetItemValue(id, "smart:rules", string(raw))
	h.franchisePoster(id)
	writeJSON(w, http.StatusOK, map[string]any{"Id": id, "Count": len(members)})
}

// smartRoom is the private library a collection belongs in, when a rule
// names one; "" is the Collections library.
func (h CollectionSuggestHandler) smartRoom(rules store.SmartRules) string {
	private := map[string]bool{}
	for _, f := range h.privateFolders() {
		private[f] = true
	}
	for _, r := range rules.Rules {
		if r.Field == "library" && r.Op == "is" {
			var folder string
			h.Store.DB.QueryRow(`SELECT folder_id FROM library_folder WHERE view_id = ? LIMIT 1`, r.Value).Scan(&folder)
			if private[folder] {
				return folder
			}
		}
	}
	return ""
}

// KeepSmartFresh re-reads every smart collection's rules every ten minutes —
// cheap queries, so a title added, watched or rated shows up where it now
// belongs without anyone pressing anything.
func (h CollectionSuggestHandler) KeepSmartFresh() {
	go func() {
		for {
			time.Sleep(10 * time.Minute)
			private := h.privateFolders()
			for id, rules := range h.Store.SmartCollections() {
				members, err := h.Store.SmartMembers(rules, private)
				if err != nil {
					continue
				}
				a, r := h.Store.SyncLinks(id, members)
				h.Store.SetLinkOrder(id, members)
				if a+r > 0 {
					h.franchisePoster(id)
				}
			}
		}
	}()
}
