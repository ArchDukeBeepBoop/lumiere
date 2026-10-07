package subs

import (
	"bufio"
	"context"
	"encoding/binary"
	"fmt"
	"math"
	"os"
	"os/exec"
	"time"
)

// Lining a subtitle up with what is actually being said.
//
// The method is ffsubsync's, and it is simpler than it sounds. Reduce both
// sides to the same thing — a track at ten samples a second saying "somebody
// is speaking here" — then slide one against the other and keep the shift
// where they agree most. The audio's version comes from its loudness; the
// subtitle's from its cue timings. Nothing is transcribed and nothing is
// understood: it is two square waves and a correlation.
//
// This is what a release with the wrong timing needs: an Inuyasha rip cut
// for a different broadcast master is not a little late, it is a constant
// thirty seconds out, and every line lands on the wrong shot for twenty-four
// minutes. One number fixes the whole episode.

// sampleRate is the speech track's resolution: ten samples a second. Finer
// buys nothing — a subtitle line is seconds long — and costs the search.
const sampleRate = 10

// MaxShift is the default for how far out a subtitle may be and still be
// found — the owner can widen or narrow it per request. A minute
// each way covers a different master, an added recap and a missing advert
// break; beyond that the answer is more likely to be a coincidence than a
// correction.
const MaxShift = 60 * time.Second

// MinConfidence is the lowest score worth acting on without being asked.
//
// Measured rather than guessed: on this library a subtitle synced against
// its own episode scores 0.5 to 0.9, and one episode's subtitle against
// another's audio — the worst case, same show, same music, same voices —
// scores 0.25. Between those sits the line.
const MinConfidence = 0.4

// Sync returns how many seconds a subtitle should be shifted to match the
// audio: positive means the subtitle is early and should be pushed later.
//
// The confidence is how much better the best shift is than the average one,
// as a fraction. A sync nobody can trust is worse than none, so a caller is
// expected to refuse a low one rather than apply it quietly.
func Sync(ctx context.Context, ffmpeg, video, subtitle string, audioTrack int, maxShift time.Duration) (offset float64, confidence float64, err error) {
	if maxShift <= 0 {
		maxShift = MaxShift
	}
	file, err := os.Open(subtitle)
	if err != nil {
		return 0, 0, err
	}
	cues := ParseCues(file)
	file.Close()
	if len(cues) < 10 {
		return 0, 0, fmt.Errorf("subtitle has %d usable lines", len(cues))
	}

	speech, duration, err := AudioSpeech(ctx, ffmpeg, video, audioTrack)
	if err != nil {
		return 0, 0, err
	}
	subtitleTrack := SpeechTrack(cues, sampleRate, duration)
	if len(subtitleTrack) == 0 || len(speech) == 0 {
		return 0, 0, fmt.Errorf("nothing to compare")
	}
	shift, score := bestShift(centred(speech), centred(subtitleTrack), int(maxShift.Seconds())*sampleRate)
	return float64(shift) / float64(sampleRate), score, nil
}

// AudioSpeech reduces a file's audio to a speech track: true where the
// sound is loud enough, ten samples a second.
//
// ffmpeg decodes one channel at 8 kHz — telephone quality, which is ample
// for "is anyone talking" — and the samples are folded into tenth-second
// buckets by their peak. The threshold is relative to the file's own median,
// because a quiet mix and a loud one are both perfectly ordinary.
func AudioSpeech(ctx context.Context, ffmpeg, video string, audioTrack int) ([]bool, time.Duration, error) {
	selector := "a:0"
	if audioTrack > 0 {
		selector = fmt.Sprintf("a:%d", audioTrack)
	}
	command := exec.CommandContext(ctx, ffmpeg,
		"-v", "error", "-i", video,
		"-map", "0:"+selector,
		"-ac", "1", "-ar", "8000",
		"-f", "s16le", "-acodec", "pcm_s16le", "-")
	output, err := command.StdoutPipe()
	if err != nil {
		return nil, 0, err
	}
	if err := command.Start(); err != nil {
		return nil, 0, err
	}
	defer command.Wait()

	const perBucket = 8000 / sampleRate
	reader := bufio.NewReaderSize(output, 1<<20)
	var peaks []float64
	buffer := make([]byte, perBucket*2)
	for {
		read, err := readFull(reader, buffer)
		if read == 0 {
			break
		}
		peak := 0.0
		for i := 0; i+1 < read; i += 2 {
			sample := math.Abs(float64(int16(binary.LittleEndian.Uint16(buffer[i : i+2]))))
			if sample > peak {
				peak = sample
			}
		}
		peaks = append(peaks, peak)
		if err != nil {
			break
		}
	}
	if len(peaks) == 0 {
		return nil, 0, fmt.Errorf("no audio decoded")
	}

	// The threshold: a quarter of the loud end. Median would sit inside
	// speech for a talkative film and inside silence for a quiet one; a
	// fraction of the loudest tenth is stable across both.
	loud := quantile(peaks, 0.9)
	threshold := loud * 0.25
	track := make([]bool, len(peaks))
	for i, peak := range peaks {
		track[i] = peak > threshold
	}
	return track, time.Duration(len(peaks)) * time.Second / sampleRate, nil
}

// bestShift slides the subtitle track across the audio and returns the shift
// in samples that agrees most, with how much it stands out.
//
// The confidence is the peak against its best rival — the highest score more
// than two seconds away from the winner — rather than against the average of
// every shift tried. The average is a poor yardstick because correlation is
// smooth: the shifts either side of the right answer score nearly as well,
// which drags the average up and makes a good answer look uncertain. A real
// alignment beats everything outside its own shoulder by a wide margin; a
// coincidence has a rival just as good somewhere else.
func bestShift(audio, subtitle []float64, window int) (int, float64) {
	scores := make([]float64, 0, 2*window+1)
	best, bestScore := 0, -1.0
	for shift := -window; shift <= window; shift++ {
		score := agreement(audio, subtitle, shift)
		scores = append(scores, score)
		if score > bestScore {
			best, bestScore = shift, score
		}
	}
	if bestScore <= 0 {
		return 0, 0
	}
	// Two seconds: wide enough to clear the peak's own shoulder, narrow
	// enough that a genuinely different alignment still counts as a rival.
	const guard = 2 * sampleRate
	rival := 0.0
	for i, score := range scores {
		shift := i - window
		if abs(shift-best) <= guard {
			continue
		}
		if score > rival {
			rival = score
		}
	}
	if rival <= 0 {
		return best, 1
	}
	confidence := 1 - rival/bestScore
	if confidence < 0 {
		confidence = 0
	}
	return best, confidence
}

func abs(value int) int {
	if value < 0 {
		return -value
	}
	return value
}

// agreement is the dot product of the two centred tracks at one shift.
//
// Centred, which is the difference between a number that means something and
// one that does not: an anime's audio is loud through most of an episode, so
// counting "both say speech" scores highly at every shift and the right
// answer barely stands out. Against the mean, silence where the subtitle is
// silent counts as agreement too, and speech where the subtitle is silent
// counts against — so the peak is sharp.
func agreement(audio, subtitle []float64, shift int) float64 {
	sum := 0.0
	for i, value := range subtitle {
		j := i + shift
		if j < 0 || j >= len(audio) {
			continue
		}
		sum += value * audio[j]
	}
	return sum
}

// centred turns a speech track into ±values about its own mean.
func centred(track []bool) []float64 {
	if len(track) == 0 {
		return nil
	}
	speaking := 0
	for _, value := range track {
		if value {
			speaking++
		}
	}
	mean := float64(speaking) / float64(len(track))
	out := make([]float64, len(track))
	for i, value := range track {
		if value {
			out[i] = 1 - mean
		} else {
			out[i] = -mean
		}
	}
	return out
}

func quantile(values []float64, q float64) float64 {
	sorted := append([]float64(nil), values...)
	quickSort(sorted)
	index := int(float64(len(sorted)-1) * q)
	return sorted[index]
}

func quickSort(values []float64) {
	if len(values) < 2 {
		return
	}
	pivot := values[len(values)/2]
	left, right := 0, len(values)-1
	for left <= right {
		for values[left] < pivot {
			left++
		}
		for values[right] > pivot {
			right--
		}
		if left <= right {
			values[left], values[right] = values[right], values[left]
			left++
			right--
		}
	}
	quickSort(values[:right+1])
	quickSort(values[left:])
}

// readFull fills buffer, returning what it got and any terminal error.
func readFull(reader *bufio.Reader, buffer []byte) (int, error) {
	read := 0
	for read < len(buffer) {
		n, err := reader.Read(buffer[read:])
		read += n
		if err != nil {
			return read, err
		}
	}
	return read, nil
}
