package api

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEachAndroidAppHasItsOwnUpdate(t *testing.T) {
	data := t.TempDir()
	for dir, code := range map[string]string{"android": "1", "android/quest": "2"} {
		os.MkdirAll(filepath.Join(data, dir), 0o755)
		os.WriteFile(filepath.Join(data, dir, "version.json"), []byte(`{"VersionCode": `+code+`}`), 0o644)
	}
	h := AndroidHandler{DataDir: data}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /Lumiere/Android/Latest", h.Latest)
	mux.HandleFunc("GET /Lumiere/Android/{channel}/Latest", h.Latest)
	ask := func(path string) (int, string) {
		w := httptest.NewRecorder()
		mux.ServeHTTP(w, httptest.NewRequest("GET", path, nil))
		return w.Code, w.Body.String()
	}
	if code, body := ask("/Lumiere/Android/Latest"); code != 200 || !strings.Contains(body, `"VersionCode":1`) {
		t.Fatalf("the TV's: %d %s", code, body)
	}
	if code, body := ask("/Lumiere/Android/quest/Latest"); code != 200 || !strings.Contains(body, `"VersionCode":2`) {
		t.Fatalf("the Quest's: %d %s", code, body)
	}
	if code, _ := ask("/Lumiere/Android/phone/Latest"); code != 404 {
		t.Fatal("no phone copy published yet: 404")
	}
	if code, _ := ask("/Lumiere/Android/..%2f..%2fetc/Latest"); code != 404 {
		t.Fatal("only the named channels")
	}
}
