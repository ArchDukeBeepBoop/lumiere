package media

import (
	"bytes"
	"image"
	"os"
	"testing"
)

// The poster that went blank: a WebP uploaded through the artwork picker.
func TestWebPDecodes(t *testing.T) {
	// Only on the machine that hit the bug; skipped elsewhere.
	sample := os.Getenv("LUMIERE_WEBP_SAMPLE")
	body, err := os.ReadFile(sample)
	if err != nil {
		t.Skip("no local sample")
	}
	img, format, err := image.Decode(bytes.NewReader(body))
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	if format != "webp" || img.Bounds().Dx() == 0 {
		t.Errorf("format %q, width %d", format, img.Bounds().Dx())
	}
}
