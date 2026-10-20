package themeart

import (
	"image"
	"image/color"
	"image/jpeg"
	_ "image/png"
	"math"
	"os"

	"golang.org/x/image/draw"
)

// The drawing primitives the two layouts are made of: loading, covering a
// frame, blurring, washes, gradients, rounded cards with a soft shadow.

func load(path string) image.Image {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	img, _, err := image.Decode(f)
	if err != nil {
		return nil
	}
	return img
}

func save(img image.Image, out string) error {
	f, err := os.Create(out)
	if err != nil {
		return err
	}
	defer f.Close()
	return jpeg.Encode(f, img, &jpeg.Options{Quality: 90})
}

// cover scales src to fill r, cropping the overflow from the centre.
func cover(dst draw.Image, r image.Rectangle, src image.Image, op draw.Op) {
	sb := src.Bounds()
	sw, sh := float64(sb.Dx()), float64(sb.Dy())
	rw, rh := float64(r.Dx()), float64(r.Dy())
	crop := sb
	if sw/sh > rw/rh {
		w := int(sh * rw / rh)
		x := sb.Min.X + (sb.Dx()-w)/2
		crop = image.Rect(x, sb.Min.Y, x+w, sb.Max.Y)
	} else {
		h := int(sw * rh / rw)
		y := sb.Min.Y + (sb.Dy()-h)/2
		crop = image.Rect(sb.Min.X, y, sb.Max.X, y+h)
	}
	draw.CatmullRom.Scale(dst, r, src, crop, op, nil)
}

// blurred is src covering a w×h frame, heavily softened: shrunk to a few
// dozen pixels and grown back, twice, which is a blur for the cost of two
// resamples.
func blurred(src image.Image, w, h int) *image.RGBA {
	cur := image.NewRGBA(image.Rect(0, 0, w/32+1, h/32+1))
	cover(cur, cur.Bounds(), src, draw.Src)
	// Grown back in doublings: one 32× stretch shows its blocks, five
	// doublings do not.
	for cur.Bounds().Dx() < w {
		nw, nh := cur.Bounds().Dx()*2, cur.Bounds().Dy()*2
		if nw > w {
			nw, nh = w, h
		}
		next := image.NewRGBA(image.Rect(0, 0, nw, nh))
		draw.BiLinear.Scale(next, next.Bounds(), cur, cur.Bounds(), draw.Src, nil)
		cur = next
	}
	if cur.Bounds().Dx() != w || cur.Bounds().Dy() != h {
		out := image.NewRGBA(image.Rect(0, 0, w, h))
		draw.BiLinear.Scale(out, out.Bounds(), cur, cur.Bounds(), draw.Src, nil)
		return out
	}
	return cur
}

// wash lays a colour over the whole of dst at the given opacity.
func wash(dst draw.Image, c color.RGBA, alpha float64) {
	c.A = uint8(alpha * 255)
	draw.Draw(dst, dst.Bounds(), &image.Uniform{premul(c)}, image.Point{}, draw.Over)
}

// gradient darkens from `from` to `to` (rows if vertical, columns if not),
// opacity rising from a0 to a1 along the way.
func gradient(dst draw.Image, vertical bool, from, to int, a0, a1 float64) {
	b := dst.Bounds()
	steps := to - from
	for i := 0; i < steps; i++ {
		t := float64(i) / float64(steps)
		a := a0 + (a1-a0)*t*t*(3-2*t)
		c := &image.Uniform{premul(color.RGBA{0, 0, 0, uint8(a * 255)})}
		var r image.Rectangle
		if vertical {
			r = image.Rect(b.Min.X, from+i, b.Max.X, from+i+1)
		} else {
			r = image.Rect(from+i, b.Min.Y, from+i+1, b.Max.Y)
		}
		draw.Draw(dst, r, c, image.Point{}, draw.Over)
	}
	if vertical && to < b.Max.Y {
		draw.Draw(dst, image.Rect(b.Min.X, to, b.Max.X, b.Max.Y),
			&image.Uniform{premul(color.RGBA{0, 0, 0, uint8(a1 * 255)})}, image.Point{}, draw.Over)
	}
}

func premul(c color.RGBA) color.RGBA {
	a := float64(c.A) / 255
	return color.RGBA{uint8(float64(c.R) * a), uint8(float64(c.G) * a), uint8(float64(c.B) * a), c.A}
}

// rounded is an alpha mask of a w×h rectangle with corners of radius rad.
func rounded(w, h, rad int) *image.Alpha {
	m := image.NewAlpha(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dx, dy := 0.0, 0.0
			if x < rad {
				dx = float64(rad - x)
			} else if x >= w-rad {
				dx = float64(x - (w - rad - 1))
			}
			if y < rad {
				dy = float64(rad - y)
			} else if y >= h-rad {
				dy = float64(y - (h - rad - 1))
			}
			d := math.Hypot(dx, dy)
			switch {
			case dx == 0 || dy == 0, d <= float64(rad)-1:
				m.SetAlpha(x, y, color.Alpha{255})
			case d < float64(rad):
				m.SetAlpha(x, y, color.Alpha{uint8((float64(rad) - d) * 255)})
			}
		}
	}
	return m
}

// card draws src covering r with rounded corners and a soft shadow under it.
func card(dst draw.Image, r image.Rectangle, src image.Image, rad int, dim float64) {
	for i := 6; i >= 1; i-- {
		spread := i * 6
		sr := image.Rect(r.Min.X-spread/2, r.Min.Y+spread/2, r.Max.X+spread/2, r.Max.Y+spread)
		m := rounded(sr.Dx(), sr.Dy(), rad+spread/2)
		draw.DrawMask(dst, sr, &image.Uniform{color.RGBA{0, 0, 0, 22}}, image.Point{}, m, image.Point{}, draw.Over)
	}
	tile := image.NewRGBA(image.Rect(0, 0, r.Dx(), r.Dy()))
	cover(tile, tile.Bounds(), src, draw.Src)
	if dim > 0 {
		wash(tile, color.RGBA{0, 0, 0, 255}, dim)
	}
	draw.DrawMask(dst, r, tile, image.Point{}, rounded(r.Dx(), r.Dy(), rad), image.Point{}, draw.Over)
}

// accent is a theme's own colour, from its name: bright, a little muted.
func accent(key string) color.RGBA {
	var h uint32 = 2166136261
	for i := 0; i < len(key); i++ {
		h = (h ^ uint32(key[i])) * 16777619
	}
	hue := float64(h%360) / 60
	s, v := 0.55, 1.0
	c := v * s
	x := c * (1 - math.Abs(math.Mod(hue, 2)-1))
	var r, g, b float64
	switch int(hue) {
	case 0:
		r, g = c, x
	case 1:
		r, g = x, c
	case 2:
		g, b = c, x
	case 3:
		g, b = x, c
	case 4:
		r, b = x, c
	default:
		r, b = c, x
	}
	m := v - c
	return color.RGBA{uint8((r + m) * 255), uint8((g + m) * 255), uint8((b + m) * 255), 255}
}
