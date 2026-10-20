// Package themeart designs the poster and backdrop of a theme collection —
// Immortality, Time Loops — from its own members: a blurred still for the
// ground, posters fanned across it, and the theme's name set large, each
// theme in a colour of its own.
package themeart

import (
	"fmt"
	"image"
	"image/color"
	"strings"

	"golang.org/x/image/draw"
	"golang.org/x/image/font"
	"golang.org/x/image/font/gofont/gobold"
	"golang.org/x/image/font/gofont/gomedium"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/fixed"
)

// Art is what a collection's artwork is made from.
type Art struct {
	Key       string   // the theme's slug: its colour
	Title     string   // "Time Loops"
	Count     int      // titles in it
	Posters   []string // members' poster files, best first
	Backdrops []string // members' wide art
}

// Poster writes a 1000×1500 poster.
func Poster(a Art, out string) error {
	const w, h = 1000, 1500
	canvas := ground(a, w, h)
	posters := loadAll(a.Posters, 3)
	if len(posters) == 0 {
		posters = loadAll(a.Backdrops, 3)
	}
	// Fanned: the outer two behind, a little lower and dimmer.
	slots := []struct {
		r   image.Rectangle
		dim float64
	}{
		{image.Rect(90, 300, 90+330, 300+495), 0.35},
		{image.Rect(w-90-330, 300, w-90, 300+495), 0.35},
		{image.Rect(w/2-200, 210, w/2+200, 210+600), 0},
	}
	order := []int{1, 2, 0}
	for i, p := range posters {
		if len(posters) == 1 {
			card(canvas, slots[2].r, p, 26, 0)
			break
		}
		s := slots[order[i%3]]
		card(canvas, s.r, p, 22, s.dim)
	}
	gradient(canvas, true, 860, 1180, 0, 0.88)
	ink := accent(a.Key)
	text(canvas, "COLLECTION", medium(30), 0, 1135, w, ink, 6, true)
	size := 118.0
	lines := wrap(a.Title, bold(size), 860)
	for len(lines) > 2 && size > 60 {
		size -= 8
		lines = wrap(a.Title, bold(size), 860)
	}
	y := 1135 + 30 + int(size)
	for _, l := range lines {
		text(canvas, l, bold(size), 0, y, w, color.RGBA{255, 255, 255, 255}, 0, true)
		y += int(size * 1.02)
	}
	text(canvas, plural(a.Count), medium(34), 0, y+18, w, color.RGBA{255, 255, 255, 170}, 1, true)
	return save(canvas, out)
}

// Backdrop writes a 1920×1080 backdrop: the name at the left, four stills
// in a grid at the right.
func Backdrop(a Art, out string) error {
	const w, h = 1920, 1080
	canvas := ground(a, w, h)
	gradient(canvas, false, 0, 1150, 0.9, 0)
	stills := loadAll(a.Backdrops, 4)
	tw, th, gap := 400, 225, 24
	x0, y0 := w-96-2*tw-gap, h/2-th-gap/2
	for i, s := range stills {
		r := image.Rect(x0+(i%2)*(tw+gap), y0+(i/2)*(th+gap), x0+(i%2)*(tw+gap)+tw, y0+(i/2)*(th+gap)+th)
		card(canvas, r, s, 18, 0.1)
	}
	ink := accent(a.Key)
	text(canvas, "COLLECTION", medium(30), 120, 420, 0, ink, 6, false)
	size := 128.0
	lines := wrap(a.Title, bold(size), 780)
	for len(lines) > 2 && size > 64 {
		size -= 8
		lines = wrap(a.Title, bold(size), 780)
	}
	y := 420 + 30 + int(size)
	for _, l := range lines {
		text(canvas, l, bold(size), 120, y, 0, color.RGBA{255, 255, 255, 255}, 0, false)
		y += int(size * 1.02)
	}
	text(canvas, plural(a.Count), medium(36), 120, y+20, 0, color.RGBA{255, 255, 255, 170}, 1, false)
	return save(canvas, out)
}

// ground is the softened still under everything, tinted the theme's colour.
func ground(a Art, w, h int) *image.RGBA {
	var src image.Image
	for _, p := range append(append([]string{}, a.Backdrops...), a.Posters...) {
		if src = load(p); src != nil {
			break
		}
	}
	var canvas *image.RGBA
	if src != nil {
		canvas = blurred(src, w, h)
	} else {
		canvas = image.NewRGBA(image.Rect(0, 0, w, h))
		draw.Draw(canvas, canvas.Bounds(), &image.Uniform{color.RGBA{18, 18, 22, 255}}, image.Point{}, draw.Src)
	}
	wash(canvas, color.RGBA{0, 0, 0, 255}, 0.55)
	wash(canvas, accent(a.Key), 0.16)
	return canvas
}

func loadAll(paths []string, n int) []image.Image {
	var out []image.Image
	for _, p := range paths {
		if len(out) == n {
			break
		}
		if img := load(p); img != nil {
			out = append(out, img)
		}
	}
	return out
}

func plural(n int) string {
	if n == 1 {
		return "1 title"
	}
	return fmt.Sprintf("%d titles", n)
}

func face(ttf []byte, size float64) font.Face {
	f, _ := opentype.Parse(ttf)
	fc, _ := opentype.NewFace(f, &opentype.FaceOptions{Size: size, DPI: 72, Hinting: font.HintingFull})
	return fc
}

func bold(size float64) font.Face   { return face(gobold.TTF, size) }
func medium(size float64) font.Face { return face(gomedium.TTF, size) }

// wrap breaks a title into lines no wider than max.
func wrap(s string, f font.Face, max int) []string {
	var lines []string
	line := ""
	for _, word := range strings.Fields(s) {
		next := strings.TrimSpace(line + " " + word)
		if line != "" && font.MeasureString(f, next).Ceil() > max {
			lines = append(lines, line)
			line = word
		} else {
			line = next
		}
	}
	if line != "" {
		lines = append(lines, line)
	}
	return lines
}

// text draws s with its baseline at y: centred in [0,width) when centred,
// else from x. Tracking adds space between letters, in pixels.
func text(dst draw.Image, s string, f font.Face, x, y, width int, c color.RGBA, tracking int, centred bool) {
	runes := []rune(s)
	total := font.MeasureString(f, s).Ceil() + tracking*(len(runes)-1)
	if centred {
		x = (width - total) / 2
	}
	d := &font.Drawer{Dst: dst, Src: &image.Uniform{premul(c)}, Face: f, Dot: fixed.P(x, y)}
	for _, r := range runes {
		d.DrawString(string(r))
		d.Dot.X += fixed.I(tracking)
	}
}
