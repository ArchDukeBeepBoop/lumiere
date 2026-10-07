package media

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	_ "image/gif"
	"image/jpeg"
	"image/png"

	// Registered for their side effect: image.Decode learns the format.
	// WebP is what most posters downloaded from the web are now, and an
	// upload of one produced a row the server could not read — the tile
	// went blank rather than showing the picture just chosen.
	_ "golang.org/x/image/webp"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// ImageCache serves artwork, resizing on first request and keeping the result.
//
// It never copies an original. Jellyfin's metadata tree is 23 GB across 101,975
// files and both servers read it in place; what lands in this cache is only the
// small variants the client actually asks for, at seven widths it is known to
// request. Deleting the whole cache costs a re-resize and nothing else.
type ImageCache struct {
	Dir string // where variants live; disposable

	// MaxBytes bounds the tree. Zero means defaultMaxBytes.
	MaxBytes int64

	prune pruner

	// One resize per (file, width) even when a home screen asks for the same
	// poster from six tiles at once. Without this a cold grid decodes the same
	// 800 KB JPEG dozens of times in parallel, which is the one place this
	// server could plausibly peg a CPU.
	inflight sync.Map
}

// Variant is a resized image ready to serve.
type Variant struct {
	Bytes       []byte
	ContentType string
}

var errUnsupported = errors.New("image format cannot be resized here")

// Get returns the artwork at path, capped to maxWidth.
//
// srcWidth is what the importer recorded, so the common "no resize needed" case
// is decided without opening the file at all.
func (c *ImageCache) Get(path, tag string, srcWidth, maxWidth, quality int) (Variant, error) {
	// Serve the original when no cap applies, when the cap is wider than the
	// picture, or when the format is one Go cannot decode — 42 webp and 35 svg
	// files here. Handing back the original is right in all three cases: the
	// client scales what it gets, and re-encoding a file we cannot read is not
	// on the table.
	if maxWidth <= 0 || (srcWidth > 0 && maxWidth >= srcWidth) || !resizable(path) {
		raw, err := os.ReadFile(path)
		if err != nil {
			return Variant{}, err
		}
		return Variant{Bytes: raw, ContentType: contentType(path)}, nil
	}

	if quality <= 0 || quality > 100 {
		quality = 90
	}
	// PNG in, PNG out. JPEG has no alpha channel, so re-encoding a logo through
	// it does not drop the transparency — it fills it, and Go's encoder fills it
	// with black. A show's logo arrived as a white wordmark in a black box, and
	// every logo wide enough to need resizing got one: below that width the
	// original file is served untouched, which is why this looked intermittent.
	out := outputFormat(path)
	key := c.cachePath(tag, maxWidth, quality, out.ext)
	if raw, err := os.ReadFile(key); err == nil {
		return Variant{Bytes: raw, ContentType: out.contentType}, nil
	}

	// Collapse concurrent misses for the same variant onto one resize.
	gate, _ := c.inflight.LoadOrStore(key, &sync.Mutex{})
	mu := gate.(*sync.Mutex)
	mu.Lock()
	defer mu.Unlock()
	defer c.inflight.Delete(key)

	// Another request may have finished it while this one waited.
	if raw, err := os.ReadFile(key); err == nil {
		return Variant{Bytes: raw, ContentType: out.contentType}, nil
	}

	encoded, err := c.render(path, maxWidth, quality, out)
	if err != nil {
		return Variant{}, err
	}
	// A smaller picture is not always fewer bytes. Re-encoding a 1280x720 poster
	// down to 960 at quality 90 measured 79 KB against the original's 43 KB,
	// because Jellyfin's own encoder had already compressed it harder than we
	// do. Serving the larger file would be worse in both directions — more
	// bytes and less detail — so the original wins whenever it is smaller.
	if raw, err := os.ReadFile(path); err == nil && len(raw) <= len(encoded) {
		return Variant{Bytes: raw, ContentType: contentType(path)}, nil
	}
	// Written through a temporary file and renamed: a half-written variant that
	// a later request reads back as a truncated JPEG would be cached forever,
	// since the client caches on the tag and never revalidates.
	c.maybePrune(len(encoded))
	if err := writeAtomic(key, encoded); err != nil {
		// A cache that cannot be written is a slow server, not a broken one.
		return Variant{Bytes: encoded, ContentType: out.contentType}, nil
	}
	return Variant{Bytes: encoded, ContentType: out.contentType}, nil
}

// format is how a resized variant is written back out.
type format struct {
	ext         string
	contentType string
	alpha       bool
}

// outputFormat keeps a source that can carry transparency in a format that can.
//
// Decided from the source extension rather than by inspecting pixels: an opaque
// PNG re-encoded as PNG is merely larger, and the guard above — serve the
// original whenever it is smaller — catches that case anyway. Guessing wrong the
// other way is not recoverable, because the alpha is gone by then.
func outputFormat(path string) format {
	if strings.EqualFold(filepath.Ext(path), ".png") {
		return format{ext: "png", contentType: "image/png", alpha: true}
	}
	return format{ext: "jpg", contentType: "image/jpeg"}
}

func (c *ImageCache) render(path string, maxWidth, quality int, out format) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	src, _, err := image.Decode(f)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", errUnsupported, err)
	}
	b := src.Bounds()
	w, h := fit(b.Dx(), b.Dy(), maxWidth)

	var buf bytes.Buffer
	if out.alpha {
		if err := png.Encode(&buf, downscale(src, w, h)); err != nil {
			return nil, err
		}
		return buf.Bytes(), nil
	}
	// Quality comes from the request. Lumiere sends 90 on every call, and the
	// difference from 100 is invisible at poster size while roughly halving the
	// bytes — but honouring the parameter costs nothing and means a client that
	// wants cheaper thumbnails can ask for them.
	if err := jpeg.Encode(&buf, downscale(src, w, h), &jpeg.Options{Quality: quality}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// cachePath keys on the tag, not the item or the path.
//
// The tag is already a content address — it changes when and only when the
// picture does — so two items sharing artwork share one variant, and stale
// entries can never be served under a new tag.
func (c *ImageCache) cachePath(tag string, maxWidth, quality int, ext string) string {
	if len(tag) < 4 {
		tag = tag + "0000"
	}
	// Two levels of fan-out: 100,000 files in one directory is slow to stat on
	// every filesystem worth naming.
	// Quality is in the key: two clients asking for the same width at different
	// qualities must not be served each other's bytes.
	return filepath.Join(c.Dir, tag[:2], tag[2:4],
		fmt.Sprintf("%s-w%d-q%d.%s", tag, maxWidth, quality, ext))
}

func writeAtomic(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tmp-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

func resizable(path string) bool {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".jpg", ".jpeg", ".png", ".gif":
		return true
	}
	return false
}

func contentType(path string) string {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	case ".svg":
		return "image/svg+xml"
	}
	return "application/octet-stream"
}
