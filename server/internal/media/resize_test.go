package media

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"testing"
)

func TestFit(t *testing.T) {
	for _, c := range []struct{ w, h, max, wantW, wantH int }{
		{1920, 1080, 320, 320, 180},
		{1998, 1080, 320, 320, 173}, // rounds rather than truncating to 172
		{1000, 1500, 300, 300, 450}, // a poster, taller than wide
		{100, 100, 500, 100, 100},   // never enlarges
		{100, 100, 0, 100, 100},     // no cap
	} {
		gotW, gotH := fit(c.w, c.h, c.max)
		if gotW != c.wantW || gotH != c.wantH {
			t.Errorf("fit(%d,%d,%d) = %dx%d, want %dx%d",
				c.w, c.h, c.max, gotW, gotH, c.wantW, c.wantH)
		}
	}
}

// Averaging, not sampling: a checkerboard shrunk to one pixel must be grey.
// Bilinear or nearest-neighbour would return black or white, which is the
// visible failure — moiré on fine detail like closing credits or star fields.
func TestDownscaleAverages(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 8, 8))
	for y := 0; y < 8; y++ {
		for x := 0; x < 8; x++ {
			c := color.RGBA{0, 0, 0, 255}
			if (x+y)%2 == 0 {
				c = color.RGBA{255, 255, 255, 255}
			}
			src.Set(x, y, c)
		}
	}
	got := downscale(src, 1, 1)
	r, g, b, _ := got.At(0, 0).RGBA()
	for _, v := range []uint32{r, g, b} {
		if mid := v >> 8; mid < 120 || mid > 136 {
			t.Fatalf("checkerboard averaged to %d, want ~128", mid)
		}
	}
}

func TestDownscaleNeverEnlarges(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 4, 4))
	if got := downscale(src, 100, 100); got.Bounds().Dx() != 4 {
		t.Fatalf("enlarged to %v", got.Bounds())
	}
}

// Every source pixel must land in exactly one destination pixel: a solid colour
// must survive a shrink unchanged, at any ratio, including ones that do not
// divide evenly.
func TestDownscalePreservesSolidColour(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 97, 61))
	for y := 0; y < 61; y++ {
		for x := 0; x < 97; x++ {
			src.Set(x, y, color.RGBA{40, 80, 120, 255})
		}
	}
	got := downscale(src, 13, 9)
	for y := 0; y < 9; y++ {
		for x := 0; x < 13; x++ {
			r, g, b, a := got.At(x, y).RGBA()
			if r>>8 != 40 || g>>8 != 80 || b>>8 != 120 || a>>8 != 255 {
				t.Fatalf("pixel %d,%d = %d,%d,%d,%d", x, y, r>>8, g>>8, b>>8, a>>8)
			}
		}
	}
}

// The YCbCr fast path must agree with the generic one. It exists only to move
// the colour conversion from once per source pixel to once per destination
// pixel; if it also changed the picture it would be a different resizer, and
// the difference would show as a colour shift on every JPEG in the library.
func TestYCbCrPathMatchesGenericPath(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 200, 300))
	for y := 0; y < 300; y++ {
		for x := 0; x < 200; x++ {
			src.Set(x, y, color.RGBA{uint8(x), uint8(y), uint8(x ^ y), 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, src, &jpeg.Options{Quality: 100}); err != nil {
		t.Fatal(err)
	}
	decoded, err := jpeg.Decode(bytes.NewReader(buf.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	ycbcr, ok := decoded.(*image.YCbCr)
	if !ok {
		t.Skipf("jpeg decoded to %T, not YCbCr", decoded)
	}

	fast := downscale(ycbcr, 40, 60)
	slow := image.NewRGBA(image.Rect(0, 0, 40, 60))
	genericDownscale(ycbcr, slow, 40, 60)

	worst := 0
	for y := 0; y < 60; y++ {
		for x := 0; x < 40; x++ {
			fr, fg, fb, _ := fast.At(x, y).RGBA()
			sr, sg, sb, _ := slow.At(x, y).RGBA()
			for _, d := range []int{
				int(fr>>8) - int(sr>>8), int(fg>>8) - int(sg>>8), int(fb>>8) - int(sb>>8),
			} {
				if d < 0 {
					d = -d
				}
				if d > worst {
					worst = d
				}
			}
		}
	}
	// Not bit-identical by construction: one averages in YCbCr and the other in
	// RGB, and the conversion is not linear. A couple of levels is rounding; a
	// large number would mean the planes are being read wrongly.
	if worst > 4 {
		t.Fatalf("paths disagree by up to %d levels", worst)
	}
}
