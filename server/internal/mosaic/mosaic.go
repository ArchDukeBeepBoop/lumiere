// Package mosaic makes a poster for a collection out of its members' posters.
//
// A collection made in the app arrived with no artwork at all, so it sat in
// every grid as a blank card — the two made tonight are the only two of 142
// with no poster. Plex and Infuse fill that gap the same way: the first four
// members, two by two.
package mosaic

import (
	"image"
	"image/color"
	"image/jpeg"
	_ "image/png"
	"os"

	"golang.org/x/image/draw"
)

// Poster proportions, 2:3, at a size a grid never upscales.
const width, height = 600, 900

// Compose writes a JPEG at `out` from up to four posters. One poster fills the
// frame; two sit side by side; three or four go two by two, the fourth cell
// repeating the first when there are three.
func Compose(posters []string, out string) error {
	var tiles []image.Image
	for _, p := range posters {
		if len(tiles) == 4 {
			break
		}
		f, err := os.Open(p)
		if err != nil {
			continue
		}
		img, _, err := image.Decode(f)
		f.Close()
		if err == nil {
			tiles = append(tiles, img)
		}
	}
	if len(tiles) == 0 {
		return os.ErrNotExist
	}
	canvas := image.NewRGBA(image.Rect(0, 0, width, height))
	draw.Draw(canvas, canvas.Bounds(), &image.Uniform{color.Black}, image.Point{}, draw.Src)
	for i, r := range cells(len(tiles)) {
		fill(canvas, r, tiles[i%len(tiles)])
	}
	f, err := os.Create(out)
	if err != nil {
		return err
	}
	defer f.Close()
	return jpeg.Encode(f, canvas, &jpeg.Options{Quality: 88})
}

func cells(n int) []image.Rectangle {
	half, mid := width/2, height/2
	switch n {
	case 1:
		return []image.Rectangle{image.Rect(0, 0, width, height)}
	case 2:
		return []image.Rectangle{image.Rect(0, 0, half, height), image.Rect(half, 0, width, height)}
	default:
		return []image.Rectangle{
			image.Rect(0, 0, half, mid), image.Rect(half, 0, width, mid),
			image.Rect(0, mid, half, height), image.Rect(half, mid, width, height),
		}
	}
}

// fill scales `src` to cover `r`, cropping the overflow from the centre.
func fill(dst *image.RGBA, r image.Rectangle, src image.Image) {
	sb := src.Bounds()
	sw, sh := float64(sb.Dx()), float64(sb.Dy())
	rw, rh := float64(r.Dx()), float64(r.Dy())
	crop := sb
	if sw/sh > rw/rh { // too wide: trim the sides
		w := int(sh * rw / rh)
		x := sb.Min.X + (sb.Dx()-w)/2
		crop = image.Rect(x, sb.Min.Y, x+w, sb.Max.Y)
	} else {
		h := int(sw * rh / rw)
		y := sb.Min.Y + (sb.Dy()-h)/2
		crop = image.Rect(sb.Min.X, y, sb.Max.X, y+h)
	}
	draw.CatmullRom.Scale(dst, r, src, crop, draw.Src, nil)
}
