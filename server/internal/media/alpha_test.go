package media

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

// A logo is a wordmark on transparency. Resizing it must not fill that
// transparency — JPEG has no alpha channel, and Go's encoder fills it with
// black, which is how a logo arrives in a black box.
func TestResizingAPNGKeepsItsTransparency(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "logo.png")

	img := image.NewNRGBA(image.Rect(0, 0, 400, 200))
	for y := 0; y < 200; y++ {
		for x := 0; x < 400; x++ {
			// Opaque white in the middle, transparent everywhere else.
			if x > 150 && x < 250 && y > 80 && y < 120 {
				img.Set(x, y, color.NRGBA{255, 255, 255, 255})
			} else {
				img.Set(x, y, color.NRGBA{0, 0, 0, 0})
			}
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(src, buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}

	cache := &ImageCache{Dir: filepath.Join(dir, "cache")}
	v, err := cache.Get(src, "tag12345", 400, 200, 90)
	if err != nil {
		t.Fatal(err)
	}
	if v.ContentType != "image/png" {
		t.Fatalf("content type = %q, want image/png", v.ContentType)
	}
	got, err := png.Decode(bytes.NewReader(v.Bytes))
	if err != nil {
		t.Fatalf("resized logo is not a PNG: %v", err)
	}
	if _, _, _, a := got.At(2, 2).RGBA(); a != 0 {
		t.Errorf("corner alpha = %d, want 0 — the transparency was filled in", a)
	}
}
