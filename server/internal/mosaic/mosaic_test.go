package mosaic

import (
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

func TestFourPostersMakeOne(t *testing.T) {
	dir := t.TempDir()
	var paths []string
	for i, c := range []color.RGBA{{255, 0, 0, 255}, {0, 255, 0, 255}, {0, 0, 255, 255}} {
		img := image.NewRGBA(image.Rect(0, 0, 200, 300))
		for y := 0; y < 300; y++ {
			for x := 0; x < 200; x++ {
				img.Set(x, y, c)
			}
		}
		p := filepath.Join(dir, string(rune('a'+i))+".png")
		f, _ := os.Create(p)
		png.Encode(f, img)
		f.Close()
		paths = append(paths, p)
	}
	out := filepath.Join(dir, "out.jpg")
	if err := Compose(append(paths, "/missing.jpg"), out); err != nil {
		t.Fatal(err)
	}
	f, _ := os.Open(out)
	defer f.Close()
	img, _, err := image.Decode(f)
	if err != nil {
		t.Fatal(err)
	}
	if b := img.Bounds(); b.Dx() != width || b.Dy() != height {
		t.Fatalf("size %v", b)
	}
	// Top-left red, top-right green, bottom-left blue, bottom-right red again.
	for _, probe := range []struct {
		x, y    int
		r, g, b bool
	}{{100, 100, true, false, false}, {450, 100, false, true, false}, {100, 700, false, false, true}, {450, 700, true, false, false}} {
		r, g, b, _ := img.At(probe.x, probe.y).RGBA()
		if (r > 0x8000) != probe.r || (g > 0x8000) != probe.g || (b > 0x8000) != probe.b {
			t.Errorf("cell at %d,%d is %d,%d,%d", probe.x, probe.y, r>>8, g>>8, b>>8)
		}
	}
	if Compose([]string{"/nope"}, out) == nil {
		t.Error("no readable posters should fail")
	}
}
