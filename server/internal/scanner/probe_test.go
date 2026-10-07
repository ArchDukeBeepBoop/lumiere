package scanner

import "testing"

func TestParseProbe(t *testing.T) {
	// Recorded ffprobe output, trimmed to the fields read. Against a fixture
	// rather than a file on this disk, so the test says something on a machine
	// whose media is not mounted.
	output := []byte(`{
	  "streams": [
	    {"codec_type":"video","codec_name":"h264","width":1920,"height":1080},
	    {"codec_type":"audio","codec_name":"aac"},
	    {"codec_type":"subtitle","codec_name":"subrip"}
	  ],
	  "format": {"format_name":"matroska,webm","duration":"1421.312000","bit_rate":"4581000"}
	}`)

	probe, err := parseProbe(output)
	if err != nil {
		t.Fatal(err)
	}
	if probe.DurationSeconds < 1421 || probe.DurationSeconds > 1422 {
		t.Errorf("duration = %v", probe.DurationSeconds)
	}
	if probe.VideoCodec != "h264" || probe.Width != 1920 || probe.Height != 1080 {
		t.Errorf("video = %s %dx%d", probe.VideoCodec, probe.Width, probe.Height)
	}
	if probe.AudioCodec != "aac" {
		t.Errorf("audio = %s", probe.AudioCodec)
	}
	if probe.Bitrate != 4581000 {
		t.Errorf("bitrate = %d", probe.Bitrate)
	}
}

func TestParseProbeIgnoresCoverArt(t *testing.T) {
	// A file with embedded artwork carries a second "video" stream that is one
	// still image. Taking the largest would report the cover's dimensions as
	// the film's.
	output := []byte(`{
	  "streams": [
	    {"codec_type":"video","codec_name":"hevc","width":3840,"height":2160},
	    {"codec_type":"video","codec_name":"mjpeg","width":6000,"height":6000}
	  ],
	  "format": {"format_name":"mov,mp4","duration":"60.0"}
	}`)
	probe, err := parseProbe(output)
	if err != nil {
		t.Fatal(err)
	}
	if probe.VideoCodec != "hevc" || probe.Width != 3840 {
		t.Errorf("video = %s %dx%d, want the first stream", probe.VideoCodec, probe.Width, probe.Height)
	}
}

func TestParseProbeOnGarbage(t *testing.T) {
	// ffprobe printing nothing useful is a file this cannot describe, not a
	// scan that should stop.
	if _, err := parseProbe([]byte("not json")); err == nil {
		t.Error("want an error rather than a zero Probe presented as fact")
	}
}
