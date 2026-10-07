package scanner

import (
	"context"
	"encoding/json"
	"os"
	"os/exec"
	"strconv"
	"time"
)

// Probe is what a file says about itself.
type Probe struct {
	DurationSeconds float64
	Container       string
	VideoCodec      string
	AudioCodec      string
	Width, Height   int
	Bitrate         int64
}

// ffprobePaths are where the tool is looked for, in order.
//
// The PATH first, then Homebrew's two prefixes. Not because a media server
// should hunt for its own dependencies, but because this one is launched by a
// menu-bar app rather than a shell: LumiereControl's environment has none of the
// PATH a terminal does, so `exec.LookPath` alone finds nothing on a machine
// where ffprobe is plainly installed.
var ffprobePaths = []string{
	// Jellyfin's own copy, which on the machine this was built for is the
	// only one there is: no Homebrew ffmpeg was ever installed, and every
	// probe had been silently skipped — no runtime on any scanned file.
	"/Applications/Jellyfin.app/Contents/MacOS/ffprobe",
	"/opt/homebrew/bin/ffprobe",
	"/usr/local/bin/ffprobe",
	"/usr/local/opt/ffmpeg/bin/ffprobe",
	"/opt/homebrew/opt/ffmpeg/bin/ffprobe",
}

// FindFFprobe returns the tool's path, or empty where there is none.
//
// Empty is not an error. A scan without a probe still finds every file and files
// it correctly — it simply cannot say how long anything is, and the runtimes
// fill in from the Jellyfin import or the next time ffprobe is present.
func FindFFprobe() string {
	if path, err := exec.LookPath("ffprobe"); err == nil {
		return path
	}
	for _, path := range ffprobePaths {
		if info, err := os.Stat(path); err == nil && !info.IsDir() {
			return path
		}
	}
	return ""
}

// ProbeFile reads one file's technical details.
//
// Bounded on purpose. A probe reads the container's header, which is fast, but
// a file on a disconnected network mount can block for as long as the OS lets
// it — and a scan of forty thousand files must not be able to stop on one of
// them.
func ProbeFile(tool, path string) (Probe, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	command := exec.CommandContext(ctx, tool,
		"-v", "quiet", "-print_format", "json",
		"-show_format", "-show_streams", path)
	output, err := command.Output()
	if err != nil {
		return Probe{}, err
	}
	return parseProbe(output)
}

// parseProbe is separate so the shape of ffprobe's answer can be tested against
// recorded output rather than against whatever happens to be on this disk.
func parseProbe(output []byte) (Probe, error) {
	var raw struct {
		Format struct {
			FormatName string `json:"format_name"`
			Duration   string `json:"duration"`
			BitRate    string `json:"bit_rate"`
		} `json:"format"`
		Streams []struct {
			CodecType string `json:"codec_type"`
			CodecName string `json:"codec_name"`
			Width     int    `json:"width"`
			Height    int    `json:"height"`
		} `json:"streams"`
	}
	if err := json.Unmarshal(output, &raw); err != nil {
		return Probe{}, err
	}

	probe := Probe{Container: raw.Format.FormatName}
	probe.DurationSeconds, _ = strconv.ParseFloat(raw.Format.Duration, 64)
	probe.Bitrate, _ = strconv.ParseInt(raw.Format.BitRate, 10, 64)

	for _, stream := range raw.Streams {
		switch stream.CodecType {
		case "video":
			// The first video stream, not the largest: a file with cover art
			// carries a second "video" stream that is one still image, and
			// taking the biggest would report an album cover's dimensions.
			if probe.VideoCodec == "" {
				probe.VideoCodec = stream.CodecName
				probe.Width, probe.Height = stream.Width, stream.Height
			}
		case "audio":
			if probe.AudioCodec == "" {
				probe.AudioCodec = stream.CodecName
			}
		}
	}
	return probe, nil
}
