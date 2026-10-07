package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"lumiere-server/internal/store"
)

func TestFirstAccountOnlyOnceAndThenSignsIn(t *testing.T) {
	s, err := store.Open(filepath.Join(t.TempDir(), "data"))
	if err != nil {
		t.Fatal(err)
	}
	h := AuthHandler{Store: s, Identity: Identity{ServerID: "srv"}, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	post := func(body string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		h.CreateAccount(rec, httptest.NewRequest("POST", "/", strings.NewReader(body)))
		return rec
	}
	if rec := post(`{"Username":"me","Password":"secret"}`); rec.Code != 200 {
		t.Fatalf("first account: %d %s", rec.Code, rec.Body)
	}
	if rec := post(`{"Username":"two","Password":"secret"}`); rec.Code != http.StatusConflict {
		t.Fatalf("second account allowed: %d", rec.Code)
	}
	account, _ := s.AccountByName("ME")
	if !verifyPassword(account.PasswordHash, "secret") || verifyPassword(account.PasswordHash, "wrong") {
		t.Fatal("hash does not verify")
	}
}

func TestLibrariesCreateListAndRemoveFolders(t *testing.T) {
	dir := t.TempDir()
	s, err := store.Open(filepath.Join(dir, "data"))
	if err != nil {
		t.Fatal(err)
	}
	films, more := filepath.Join(dir, "Films"), filepath.Join(dir, "More")
	os.Mkdir(films, 0o755)
	os.Mkdir(more, 0o755)
	h := LibrariesHandler{Store: s, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	mux := http.NewServeMux()
	h.Register(mux)
	call := func(method, path, body string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		mux.ServeHTTP(rec, httptest.NewRequest(method, path, strings.NewReader(body)))
		return rec
	}
	rec := call("POST", "/Lumiere/Libraries", `{"Name":"Films","CollectionType":"movies","Paths":["`+films+`"]}`)
	var made struct{ Id string }
	json.Unmarshal(rec.Body.Bytes(), &made)
	if rec.Code != 200 || made.Id == "" {
		t.Fatalf("create: %d %s", rec.Code, rec.Body)
	}
	if rec := call("POST", "/Lumiere/Libraries/"+made.Id+"/Folders", `{"Path":"`+films+`"}`); rec.Code != 400 {
		t.Fatalf("same folder twice: %d", rec.Code)
	}
	if rec := call("POST", "/Lumiere/Libraries/"+made.Id+"/Folders", `{"Path":"`+more+`"}`); rec.Code != 204 {
		t.Fatalf("add folder: %d %s", rec.Code, rec.Body)
	}
	libs, _ := s.ListLibraries()
	if len(libs) != 1 || libs[0].Kind != "movies" || len(libs[0].Folders) != 2 {
		t.Fatalf("list: %+v", libs)
	}
	folder := libs[0].Folders[1].ID
	if rec := call("DELETE", "/Lumiere/Libraries/"+made.Id+"/Folders/"+folder, ""); rec.Code != 204 {
		t.Fatalf("remove folder: %d", rec.Code)
	}
	if rec := call("DELETE", "/Lumiere/Libraries/"+made.Id, ""); rec.Code != 204 {
		t.Fatalf("remove library: %d", rec.Code)
	}
	if libs, _ := s.ListLibraries(); len(libs) != 0 {
		t.Fatalf("left behind: %+v", libs)
	}
	if rec := call("GET", "/Lumiere/Browse?path="+dir, ""); !strings.Contains(rec.Body.String(), "Films") {
		t.Fatalf("browse: %s", rec.Body)
	}
}
