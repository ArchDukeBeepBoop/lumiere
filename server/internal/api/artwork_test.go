package api

import "testing"

func TestImageKindIsAnAllowlist(t *testing.T) {
	// The kind becomes part of a filename, so it is chosen from a fixed set
	// rather than taken from the path.
	for raw, want := range map[string]string{
		"Primary": "Primary", "primary": "Primary",
		"backdrop": "Backdrop", "Thumb": "Thumb", "logo": "Logo",
	} {
		if got := imageKind(raw); got != want {
			t.Errorf("imageKind(%q) = %q, want %q", raw, got, want)
		}
	}
	for _, raw := range []string{"", "../../etc/passwd", "Primary/../x", "banner"} {
		if got := imageKind(raw); got != "" {
			t.Errorf("imageKind(%q) = %q, want it refused", raw, got)
		}
	}
}

func TestContentTagChangesWithTheContent(t *testing.T) {
	// The client's artwork cache keys on the tag and never revalidates, so a
	// new picture under the same name must produce a new tag or the old one is
	// shown for ever.
	a := contentTag([]byte("one picture"))
	if a == contentTag([]byte("another picture")) {
		t.Error("two pictures share a tag")
	}
	if a != contentTag([]byte("one picture")) {
		t.Error("the same picture must tag the same, or every scan re-downloads")
	}
}

func TestSniffExtensionReadsTheBytes(t *testing.T) {
	webp := append([]byte("RIFF\x00\x00\x00\x00WEBPVP8 "), make([]byte, 8)...)
	if got := sniffExtension(webp, "image/jpeg"); got != ".webp" {
		t.Errorf("webp named %s", got)
	}
	png := []byte("\x89PNG\r\n\x1a\n........")
	if got := sniffExtension(png, ""); got != ".png" {
		t.Errorf("png named %s", got)
	}
	jpg := []byte{0xFF, 0xD8, 0xFF, 0xE0, 0, 0}
	if got := sniffExtension(jpg, "image/webp"); got != ".jpg" {
		t.Errorf("jpeg named %s", got)
	}
}
