package scanner

import (
	"log/slog"

	"lumiere-server/internal/media"
	"lumiere-server/internal/store"
)

// IndexSegments reads the Matroska header of every file not yet read.
//
// Run after each scan, bounded so a first pass over a large library does not
// hold the scan; a header read is a few kilobytes and a few milliseconds, so
// a thousand a pass drains any library in a handful of scans and a new file
// is read the pass after it arrives. See media.ReadSegment for what is kept.
func IndexSegments(db *store.Store, limit int, log *slog.Logger) (int, error) {
	pending, err := db.SegmentsToIndex(limit)
	if err != nil {
		return 0, err
	}
	read := 0
	for _, file := range pending {
		seg, err := media.ReadSegment(file[1])
		if err != nil {
			// Recorded with no UID rather than skipped, or the same
			// unreadable file would be retried every pass forever.
			seg = media.Segment{}
		}
		if err := db.RecordSegment(file[0], seg); err != nil {
			return read, err
		}
		read++
	}
	if read > 0 {
		unresolved, _ := db.UnresolvedLinks()
		log.Info("segments: headers read", "files", read, "unresolved links", unresolved)
	}
	return read, nil
}
