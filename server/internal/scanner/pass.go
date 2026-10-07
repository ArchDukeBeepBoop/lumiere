package scanner

// A pass over every library at once, for the file that moved between two.
//
// Reconcile paired a missing file with a new one inside the library being
// scanned, and a file dragged from My Videos into 3D was outside its view:
// one library saw a file gone and removed its row — the picture, the watch
// state — and the other saw a stranger and gave it a bare new row. Across a
// pass, the pairing is the same and the view is wider: what any library adds
// is remembered, what any library misses is held until every library has
// been read, and only then is a file called gone.

// moveKey identifies a file across a rename or a move: two different videos
// with the same byte count and the same filename do not happen.
type moveKey struct {
	base string
	size int64
}

type missingFile struct {
	id, path string
	key      moveKey
}

type deferredLibrary struct {
	libraryID string
	known     int
	gone      []missingFile
}

type passState struct {
	added    map[moveKey]Found
	deferred []deferredLibrary
}

// BeginPass opens a multi-library pass. Until FinishPass, no missing file is
// removed; it waits for the libraries still to be read.
func (s *Scanner) BeginPass() {
	s.pass = &passState{added: map[moveKey]Found{}}
}

// FinishPass settles what every library left missing, now that every library
// has been read: a file another library added in the meantime is a move, and
// the rest are removed under each library's own guard. Returns the moves and
// removals it made.
func (s *Scanner) FinishPass() (moved, removed, missing int) {
	pass := s.pass
	s.pass = nil
	if pass == nil {
		return 0, 0, 0
	}
	for _, lib := range pass.deferred {
		var still []missingFile
		result := Result{}
		for _, m := range lib.gone {
			file, ok := pass.added[m.key]
			if !ok || m.key.size == 0 || file.Path == m.path {
				still = append(still, m)
				continue
			}
			if err := s.adoptMove(m.id, file); err != nil {
				s.Log.Info("scan: could not record move", "from", m.path, "to", file.Path, "error", err)
				continue
			}
			s.Log.Info("scan: moved across libraries", "from", m.path, "to", file.Path)
			moved++
		}
		s.settle(lib.libraryID, lib.known, still, &result)
		removed += result.Removed
		missing += result.Missing
	}
	return moved, removed, missing
}
