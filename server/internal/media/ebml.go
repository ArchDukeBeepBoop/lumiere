package media

import (
	"encoding/hex"
	"errors"
	"io"
	"os"
)

// Matroska's segment linking, read just far enough to follow it.
//
// A fansub release ships the opening and ending once, as their own files, and
// each episode carries an *ordered edition*: a chapter list whose entries say
// "play this range — and this one lives in another segment, named by UID."
// VLC and mpv follow those links to files beside the episode and play the
// whole thing as one timeline. AVFoundation does not know the feature exists,
// and ffprobe reports the chapters without the links, so the server has to
// read the header itself.
//
// Only the header is read: the Info element for the SegmentUID and the
// Chapters element for the edition. Both normally precede the first Cluster;
// where a muxer put Chapters at the end, the SeekHead says where.

const (
	idEBML           = 0x1A45DFA3
	idSegment        = 0x18538067
	idSeekHead       = 0x114D9B74
	idSeek           = 0x4DBB
	idSeekID         = 0x53AB
	idSeekPosition   = 0x53AC
	idInfo           = 0x1549A966
	idSegmentUID     = 0x73A4
	idCluster        = 0x1F43B675
	idChapters       = 0x1043A770
	idEditionEntry   = 0x45B9
	idEditionOrdered = 0x45DD
	idChapterAtom    = 0xB6
	idChapterStart   = 0x91
	idChapterEnd     = 0x92
	idChapterSegUID  = 0x6E67
	idChapterDisplay = 0x80
	idChapString     = 0x85
)

// Segment is what one file says about itself and what it borrows.
type Segment struct {
	UID     string
	Ordered bool
	// Chapters in play order, for an ordered edition. Empty otherwise.
	Chapters []LinkedChapter
}

// LinkedChapter is one range of the ordered edition. LinkUID is empty for a
// range of the file itself.
type LinkedChapter struct {
	StartNS int64
	EndNS   int64
	LinkUID string
	Title   string
}

// ReadSegment reads a file's SegmentUID and ordered edition, if any.
func ReadSegment(path string) (Segment, error) {
	f, err := os.Open(path)
	if err != nil {
		return Segment{}, err
	}
	defer f.Close()
	r := &ebmlReader{f: f}

	id, size, err := r.header()
	if err != nil || id != idEBML {
		return Segment{}, errors.New("not an EBML file")
	}
	if _, err := f.Seek(int64(size), io.SeekCurrent); err != nil {
		return Segment{}, err
	}
	id, size, err = r.header()
	if err != nil || id != idSegment {
		return Segment{}, errors.New("no Matroska segment")
	}
	segmentStart, _ := f.Seek(0, io.SeekCurrent)
	segmentEnd := segmentStart + int64(size)
	if size == 0 || size == unknownSize {
		segmentEnd = 1 << 62
	}

	var seg Segment
	var chaptersAt int64 = -1
	sawChapters := false
	for pos := segmentStart; pos < segmentEnd; {
		if _, err := f.Seek(pos, io.SeekStart); err != nil {
			break
		}
		id, size, err := r.header()
		if err != nil {
			break
		}
		body, _ := f.Seek(0, io.SeekCurrent)
		switch id {
		case idSeekHead:
			r.seekHead(body, body+int64(size), segmentStart, &chaptersAt)
		case idInfo:
			seg.UID = r.uidIn(body, body+int64(size), idSegmentUID)
		case idChapters:
			seg.Ordered, seg.Chapters = r.chapters(body, body+int64(size))
			sawChapters = true
		case idCluster:
			// Past the header. If Chapters were declared later, go there once.
			if !sawChapters && chaptersAt > 0 {
				f.Seek(chaptersAt, io.SeekStart)
				if id, size, err := r.header(); err == nil && id == idChapters {
					b, _ := f.Seek(0, io.SeekCurrent)
					seg.Ordered, seg.Chapters = r.chapters(b, b+int64(size))
				}
			}
			return seg, nil
		}
		if size == unknownSize {
			break
		}
		pos = body + int64(size)
	}
	return seg, nil
}

const unknownSize = 0x00FFFFFFFFFFFFFF

type ebmlReader struct{ f *os.File }

// vint reads an EBML variable-length integer. Element ids keep their length
// marker; sizes drop it.
func (r *ebmlReader) vint(keepMarker bool) (uint64, int, error) {
	var first [1]byte
	if _, err := io.ReadFull(r.f, first[:]); err != nil {
		return 0, 0, err
	}
	length, mask := 1, byte(0x80)
	for length <= 8 && first[0]&mask == 0 {
		mask >>= 1
		length++
	}
	if length > 8 {
		return 0, 0, errors.New("bad vint")
	}
	value := uint64(first[0])
	if !keepMarker {
		value = uint64(first[0] & (mask - 1))
	}
	rest := make([]byte, length-1)
	if _, err := io.ReadFull(r.f, rest); err != nil {
		return 0, 0, err
	}
	for _, b := range rest {
		value = value<<8 | uint64(b)
	}
	if !keepMarker && length == 8 && value == unknownSize {
		return unknownSize, length, nil
	}
	return value, length, nil
}

func (r *ebmlReader) header() (uint64, uint64, error) {
	id, _, err := r.vint(true)
	if err != nil {
		return 0, 0, err
	}
	size, _, err := r.vint(false)
	return id, size, err
}

func (r *ebmlReader) bytes(size uint64) []byte {
	if size > 1<<20 {
		return nil
	}
	buf := make([]byte, size)
	if _, err := io.ReadFull(r.f, buf); err != nil {
		return nil
	}
	return buf
}

func (r *ebmlReader) uint(size uint64) int64 {
	var v int64
	for _, b := range r.bytes(size) {
		v = v<<8 | int64(b)
	}
	return v
}

func (r *ebmlReader) uidIn(from, to int64, want uint64) string {
	for pos := from; pos < to; {
		r.f.Seek(pos, io.SeekStart)
		id, size, err := r.header()
		if err != nil {
			return ""
		}
		body, _ := r.f.Seek(0, io.SeekCurrent)
		if id == want {
			return hex.EncodeToString(r.bytes(size))
		}
		pos = body + int64(size)
	}
	return ""
}

func (r *ebmlReader) seekHead(from, to, segmentStart int64, chaptersAt *int64) {
	for pos := from; pos < to; {
		r.f.Seek(pos, io.SeekStart)
		id, size, err := r.header()
		if err != nil {
			return
		}
		body, _ := r.f.Seek(0, io.SeekCurrent)
		if id == idSeek {
			var seekID uint64
			var seekPos int64
			for p := body; p < body+int64(size); {
				r.f.Seek(p, io.SeekStart)
				cid, csize, err := r.header()
				if err != nil {
					break
				}
				cbody, _ := r.f.Seek(0, io.SeekCurrent)
				switch cid {
				case idSeekID:
					for _, b := range r.bytes(csize) {
						seekID = seekID<<8 | uint64(b)
					}
				case idSeekPosition:
					seekPos = r.uint(csize)
				}
				p = cbody + int64(csize)
			}
			if seekID == idChapters {
				*chaptersAt = segmentStart + seekPos
			}
		}
		pos = body + int64(size)
	}
}

func (r *ebmlReader) chapters(from, to int64) (bool, []LinkedChapter) {
	var ordered bool
	var out []LinkedChapter
	for pos := from; pos < to; {
		r.f.Seek(pos, io.SeekStart)
		id, size, err := r.header()
		if err != nil {
			break
		}
		body, _ := r.f.Seek(0, io.SeekCurrent)
		if id == idEditionEntry {
			edOrdered, atoms := r.edition(body, body+int64(size))
			// The first ordered edition is the one players follow.
			if edOrdered && !ordered {
				ordered, out = true, atoms
			}
		}
		pos = body + int64(size)
	}
	return ordered, out
}
