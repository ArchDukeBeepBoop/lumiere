package media

import (
	"encoding/hex"
	"io"
)

// Split from ebml.go for the 300-line rule.

func (r *ebmlReader) edition(from, to int64) (bool, []LinkedChapter) {
	var ordered bool
	var atoms []LinkedChapter
	for pos := from; pos < to; {
		r.f.Seek(pos, io.SeekStart)
		id, size, err := r.header()
		if err != nil {
			break
		}
		body, _ := r.f.Seek(0, io.SeekCurrent)
		switch id {
		case idEditionOrdered:
			ordered = r.uint(size) == 1
		case idChapterAtom:
			atoms = append(atoms, r.atom(body, body+int64(size)))
		}
		pos = body + int64(size)
	}
	return ordered, atoms
}

func (r *ebmlReader) atom(from, to int64) LinkedChapter {
	var c LinkedChapter
	for pos := from; pos < to; {
		r.f.Seek(pos, io.SeekStart)
		id, size, err := r.header()
		if err != nil {
			break
		}
		body, _ := r.f.Seek(0, io.SeekCurrent)
		switch id {
		case idChapterStart:
			c.StartNS = r.uint(size)
		case idChapterEnd:
			c.EndNS = r.uint(size)
		case idChapterSegUID:
			c.LinkUID = hex.EncodeToString(r.bytes(size))
		case idChapterDisplay:
			for p := body; p < body+int64(size); {
				r.f.Seek(p, io.SeekStart)
				cid, csize, err := r.header()
				if err != nil {
					break
				}
				cbody, _ := r.f.Seek(0, io.SeekCurrent)
				if cid == idChapString && c.Title == "" {
					c.Title = string(r.bytes(csize))
				}
				p = cbody + int64(csize)
			}
		}
		pos = body + int64(size)
	}
	return c
}
