package api

import (
	"database/sql"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// Undoing the last Move to Trash.
//
// Deleting sends the files to the Trash and drops their rows, watch history
// included. For ten minutes afterwards the server remembers what it moved and
// the watch state it dropped, so Undo can put the files back where they were
// and the history with them; the next scan re-adds the items under the ids
// their paths give them. After that, the Trash itself is the way back.

type trashMove struct{ From, To string }

type trashRecord struct {
	Moves    []trashMove
	UserData []map[string]any
	At       time.Time
}

var (
	lastTrashMu sync.Mutex
	lastTrash   *trashRecord
)

const untrashWindow = 10 * time.Minute

func rememberTrash(r trashRecord) {
	r.At = time.Now()
	lastTrashMu.Lock()
	lastTrash = &r
	lastTrashMu.Unlock()
}

// watchStateOf reads the user_data rows about to be purged, as column maps.
func (h RemovalHandler) watchStateOf(ids []string) []map[string]any {
	var out []map[string]any
	for _, id := range ids {
		rows, err := h.Store.DB.Query(`SELECT * FROM user_data WHERE item_id = ?`, id)
		if err != nil {
			continue
		}
		out = append(out, scanMaps(rows)...)
	}
	return out
}

func scanMaps(rows *sql.Rows) []map[string]any {
	defer rows.Close()
	columns, _ := rows.Columns()
	var out []map[string]any
	for rows.Next() {
		values := make([]any, len(columns))
		pointers := make([]any, len(columns))
		for i := range values {
			pointers[i] = &values[i]
		}
		if rows.Scan(pointers...) != nil {
			continue
		}
		row := map[string]any{}
		for i, c := range columns {
			row[c] = values[i]
		}
		out = append(out, row)
	}
	return out
}

// Untrash is POST /Items/Untrash — puts back the last Move to Trash, if it
// was within the last ten minutes. Answers how many files came back; the
// client then asks for a scan so the items reappear.
func (h RemovalHandler) Untrash(w http.ResponseWriter, r *http.Request) {
	lastTrashMu.Lock()
	record := lastTrash
	lastTrash = nil
	lastTrashMu.Unlock()
	if record == nil || time.Since(record.At) > untrashWindow {
		writeJSON(w, http.StatusGone, errorBody{"nothing recent to put back — it is still in the Trash"})
		return
	}
	back := 0
	// Shortest paths first: a folder goes back before anything inside it.
	for i := len(record.Moves) - 1; i >= 0; i-- {
		m := record.Moves[i]
		// Only out of a Trash, and never over something that is there now.
		if !strings.Contains(m.To, "/.Trash") {
			continue
		}
		if _, err := os.Stat(m.From); err == nil {
			continue
		}
		if os.Rename(m.To, m.From) == nil {
			back++
		}
	}
	for _, row := range record.UserData {
		columns, marks, values := []string{}, []string{}, []any{}
		for c, v := range row {
			columns, marks, values = append(columns, c), append(marks, "?"), append(values, v)
		}
		h.Store.DB.Exec(`INSERT INTO user_data (`+strings.Join(columns, ",")+`) VALUES (`+
			strings.Join(marks, ",")+`) ON CONFLICT DO NOTHING`, values...)
	}
	h.Log.Info("untrashed", "files", back, "watch_rows", len(record.UserData))
	writeJSON(w, http.StatusOK, map[string]any{"Restored": back})
}
