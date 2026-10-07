package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"sync"

	"lumiere-server/internal/store"
)

// MoveMisfiled is POST /Library/Health/MoveMisfiled {"Id": "..."} — moves a
// misfiled episode (and its sidecars) into the folder of the season its name
// gives. The client asks for a scan after, which follows the move so the item
// keeps its history. Undone by UndoMove.
func (h HealthHandler) MoveMisfiled(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Id  string
		Ids []string
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorBody{"unreadable body"})
		return
	}
	ids := body.Ids
	if body.Id != "" {
		ids = append(ids, body.Id)
	}
	// All of them, one Undo: a batch that half-worked is put back whole.
	var all []store.Move
	folder := ""
	for _, id := range ids {
		moves, dest, err := h.moveOne(store.NormalizeID(id))
		all = append(all, moves...)
		if err != nil {
			undoMoves(all)
			writeJSON(w, http.StatusConflict, errorBody{err.Error()})
			return
		}
		folder = dest
	}
	lastMoveMu.Lock()
	lastMove = all
	lastMoveMu.Unlock()
	h.Log.Info("moved misfiled episodes", "episodes", len(ids), "files", len(all))
	writeJSON(w, http.StatusOK, map[string]any{"Folder": folder, "Files": len(all), "Episodes": len(ids)})
}

func (h HealthHandler) moveOne(id string) ([]store.Move, string, error) {
	item, err := h.Store.ItemByID(id)
	if err != nil || item.Path == "" {
		return nil, "", fmt.Errorf("no such episode")
	}
	season, _, ok := store.NamedSeason(item.Path)
	if !ok {
		return nil, "", fmt.Errorf("%s gives no season", item.Name)
	}
	folder, err := store.SeasonFolderFor(item.Path, season)
	if err != nil {
		return nil, "", err
	}
	moves, err := store.MoveWithSidecars(item.Path, folder)
	return moves, folder, err
}

// UndoMove is POST /Library/Health/UndoMove — puts the last move back.
func (h HealthHandler) UndoMove(w http.ResponseWriter, r *http.Request) {
	lastMoveMu.Lock()
	moves := lastMove
	lastMove = nil
	lastMoveMu.Unlock()
	if len(moves) == 0 {
		writeJSON(w, http.StatusGone, errorBody{"nothing to put back"})
		return
	}
	undoMoves(moves)
	writeJSON(w, http.StatusOK, map[string]any{"Restored": len(moves)})
}

var (
	lastMoveMu sync.Mutex
	lastMove   []store.Move
)

func undoMoves(moves []store.Move) {
	for i := len(moves) - 1; i >= 0; i-- {
		if _, err := os.Stat(moves[i].From); err == nil {
			continue
		}
		os.Rename(moves[i].To, moves[i].From)
	}
}
