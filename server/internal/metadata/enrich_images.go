package metadata

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// FetchImage stores a TMDB picture (size and path, "w780/abc.jpg") as an
// item's picture of that kind. For collections; see the api package.
func (e *Enricher) FetchImage(itemID, kind, path string) error {
	return e.fetchImage(itemID, kind, path)
}

func (e *Enricher) fetchImage(itemID, kind, path string) error {
	response, err := e.TMDB.HTTP.Get(ImageBase + path)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("image: %s", response.Status)
	}

	// Capped: an unbounded read from a remote host is a memory budget somebody
	// else controls.
	body, err := io.ReadAll(io.LimitReader(response.Body, 12<<20))
	if err != nil {
		return err
	}

	sum := sha256.Sum256(body)
	tag := hex.EncodeToString(sum[:16])
	dir := filepath.Join(e.ImageDir, "metadata")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	extension := ".jpg"
	if strings.Contains(response.Header.Get("Content-Type"), "png") {
		extension = ".png"
	}
	file := filepath.Join(dir, itemID+"-"+strings.ToLower(kind)+extension)
	if err := os.WriteFile(file, body, 0o600); err != nil {
		return err
	}

	// The tag is the content hash, so the client's artwork cache — which keys
	// on the tag and never revalidates — busts exactly when the picture does.
	_, err = e.Store.DB.Exec(`
		INSERT INTO image (item_id, kind, idx, path, tag) VALUES (?,?,?,?,?)
		ON CONFLICT(item_id, kind, idx) DO UPDATE SET path = excluded.path, tag = excluded.tag`,
		itemID, kind, 0, file, tag)
	return err
}
