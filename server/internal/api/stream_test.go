package api

import "testing"

// The container name comes from ffprobe by way of Jellyfin, and ffprobe names
// some formats as a comma-separated list of everything the demuxer handles —
// "matroska,webm" for an MKV, "mov,mp4,m4a,3gp,3g2,mj2" for an MP4. Matching
// only the tidy names hands back application/octet-stream for a large part of
// the library.
func TestContainerMIME(t *testing.T) {
	for _, c := range []struct{ container, path, want string }{
		{"mkv", "/m/a.mkv", "video/x-matroska"},
		{"matroska,webm", "/m/a.mkv", "video/x-matroska"},
		{"mp4", "/m/a.mp4", "video/mp4"},
		{"mov,mp4,m4a,3gp,3g2,mj2", "/m/a.mp4", "video/mp4"},
		{"MKV", "/m/a.mkv", "video/x-matroska"},
		{" mkv ", "/m/a.mkv", "video/x-matroska"},
		// No container recorded: fall back to the extension rather than to
		// octet-stream, which is what the client would have to sniff past.
		{"", "/m/a.mkv", "video/x-matroska"},
		{"", "/m/a.mp4", "video/mp4"},
		{"", "/m/a.flac", "audio/flac"},
		// Genuinely unknown stays honest.
		{"", "/m/a.bin", "application/octet-stream"},
	} {
		if got := containerMIME(c.container, c.path); got != c.want {
			t.Errorf("containerMIME(%q, %q) = %q, want %q",
				c.container, c.path, got, c.want)
		}
	}
}

func TestSubtitleMIME(t *testing.T) {
	for path, want := range map[string]string{
		"/m/a.srt": "application/x-subrip",
		"/m/a.vtt": "text/vtt",
		"/m/a.ass": "text/x-ssa",
		"/m/a.sub": "text/plain; charset=utf-8",
	} {
		if got := subtitleMIME(path); got != want {
			t.Errorf("subtitleMIME(%q) = %q, want %q", path, got, want)
		}
	}
}
