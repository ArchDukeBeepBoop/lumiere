// Package media serves bytes: artwork now, video files later.
package media

import (
	"image"
	"image/color"
)

// downscale shrinks an image by averaging each destination pixel over the
// source pixels it covers.
//
// A box filter, written out rather than pulled in. golang.org/x/image/draw
// would do this in one call, and the reason not to add it is narrow: this server
// only ever shrinks — maxWidth is a cap, and anything at or above the source
// width is served as the original file without being decoded at all. Area
// averaging is the right filter for that one direction and is better than the
// bilinear sampling a general-purpose scaler would reach for, because it reads
// every source pixel instead of four of them. A 1920px backdrop going to 320px
// throws away 97% of its pixels under bilinear and moirés on fine detail; this
// does not.
//
// Not gamma-correct, deliberately: averaging in sRGB is what Jellyfin, and
// every other server the client has ever talked to, already does. Being
// correct here would make this server's posters visibly different from the
// ones already cached on the device.
func downscale(src image.Image, width, height int) image.Image {
	b := src.Bounds()
	sw, sh := b.Dx(), b.Dy()
	if width <= 0 || height <= 0 || (width >= sw && height >= sh) {
		return src
	}
	dst := image.NewRGBA(image.Rect(0, 0, width, height))
	if src, ok := src.(*image.YCbCr); ok {
		downscaleYCbCr(src, dst, width, height)
		return dst
	}

	genericDownscale(src, dst, width, height)
	return dst
}

// genericDownscale is the box filter for any image.Image.
func genericDownscale(src image.Image, dst *image.RGBA, width, height int) {
	b := src.Bounds()
	sw, sh := b.Dx(), b.Dy()
	for y := 0; y < height; y++ {
		// Source rows this destination row covers. Computed from the edges
		// rather than from a centre plus a radius, so every source pixel belongs
		// to exactly one destination pixel and none is counted twice.
		y0 := b.Min.Y + y*sh/height
		y1 := b.Min.Y + (y+1)*sh/height
		if y1 <= y0 {
			y1 = y0 + 1
		}
		for x := 0; x < width; x++ {
			x0 := b.Min.X + x*sw/width
			x1 := b.Min.X + (x+1)*sw/width
			if x1 <= x0 {
				x1 = x0 + 1
			}

			var r, g, bl, a uint64
			var n uint64
			for sy := y0; sy < y1; sy++ {
				for sx := x0; sx < x1; sx++ {
					cr, cg, cb, ca := src.At(sx, sy).RGBA()
					r += uint64(cr)
					g += uint64(cg)
					bl += uint64(cb)
					a += uint64(ca)
					n++
				}
			}
			if n == 0 {
				continue
			}
			// RGBA() returns 16-bit alpha-premultiplied values; >>8 brings them
			// back to the 8-bit premultiplied form image.RGBA stores.
			dst.SetRGBA(x, y, color.RGBA{
				R: uint8(r / n >> 8),
				G: uint8(g / n >> 8),
				B: uint8(bl / n >> 8),
				A: uint8(a / n >> 8),
			})
		}
	}
}

// fit returns the size an image should be drawn at to respect maxWidth,
// preserving aspect ratio and never enlarging.
//
// Height is rounded to the nearest rather than truncated: a 1920x1080 backdrop
// capped at 320 is 180.0 exactly, but 1998x1080 at 320 truncates to 172 where
// the honest answer is 173, and a poster grid with one tile a pixel short is
// visible.
func fit(srcW, srcH, maxWidth int) (int, int) {
	if maxWidth <= 0 || srcW <= 0 || srcH <= 0 || maxWidth >= srcW {
		return srcW, srcH
	}
	h := (srcH*maxWidth + srcW/2) / srcW
	if h < 1 {
		h = 1
	}
	return maxWidth, h
}

// downscaleYCbCr is the same box filter with the colour conversion moved to the
// end.
//
// Worth a second implementation because of where the work is. The generic path
// calls src.At(x, y) for every source pixel, and on a JPEG that means a full
// YCbCr-to-RGB conversion per pixel — 6 million of them for a 2000x3000 poster
// going to 320 wide. Here the three planes are averaged as plain integers and
// the conversion happens once per *destination* pixel: 153,600 instead of
// 6,000,000. Measured at roughly a fifth of the time on the poster sizes in
// this library.
//
// Averaging the planes separately is also what the format wants: chroma is
// already stored subsampled, so it is averaged over its own grid rather than
// resampled up and back down.
func downscaleYCbCr(src *image.YCbCr, dst *image.RGBA, width, height int) {
	b := src.Bounds()
	sw, sh := b.Dx(), b.Dy()

	for y := 0; y < height; y++ {
		y0 := b.Min.Y + y*sh/height
		y1 := b.Min.Y + (y+1)*sh/height
		if y1 <= y0 {
			y1 = y0 + 1
		}
		for x := 0; x < width; x++ {
			x0 := b.Min.X + x*sw/width
			x1 := b.Min.X + (x+1)*sw/width
			if x1 <= x0 {
				x1 = x0 + 1
			}

			var sy, scb, scr, n uint32
			for py := y0; py < y1; py++ {
				yRow := src.YOffset(x0, py)
				for px := x0; px < x1; px++ {
					sy += uint32(src.Y[yRow+px-x0])
					ci := src.COffset(px, py)
					scb += uint32(src.Cb[ci])
					scr += uint32(src.Cr[ci])
					n++
				}
			}
			if n == 0 {
				continue
			}
			r, g, bl := color.YCbCrToRGB(
				uint8(sy/n), uint8(scb/n), uint8(scr/n))
			dst.SetRGBA(x, y, color.RGBA{R: r, G: g, B: bl, A: 255})
		}
	}
}
