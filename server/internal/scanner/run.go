package scanner

import (
	"log/slog"
	"sync"
	"time"

	"lumiere-server/internal/store"
)

// Progress is what a scan says about itself while it runs.
//
// Reported per library rather than as one number, because that is the shape the
// work actually has and the shape the panel draws: nine libraries, each with a
// count that means something, instead of a bar whose percentage is an average of
// nine unrelated things.
type Progress struct {
	Running bool   `json:"Running"`
	Library string `json:"Library,omitempty"`
	// Index and Total are which library, of how many.
	Index int `json:"Index,omitempty"`
	Total int `json:"Total,omitempty"`
	// Added is the running count across the whole pass, which is the number
	// somebody pressing Scan is waiting to hear.
	Added   int `json:"Added"`
	Files   int `json:"Files"`
	Missing int `json:"Missing"`
	Moved   int `json:"Moved"`
	Removed int `json:"Removed"`
	// UnresolvedLinks are episodes whose release links an opening or ending
	// the library does not have. See store.UnresolvedLinks.
	UnresolvedLinks int `json:"UnresolvedLinks"`
	Probed          int `json:"Probed"`
	// RepairedAt is when a pass last rewrote rows a client may already hold.
	// Filled in by the status handler from the store, not by the pass.
	RepairedAt string `json:"RepairedAt,omitempty"`
	// Changed moves whenever watch state or the catalogue does, from any
	// writer. Clients poll it cheaply and sync only when it moves. Filled in
	// by the status handler, like RepairedAt.
	Changed string `json:"Changed,omitempty"`
	Started string `json:"Started,omitempty"`
	Ended   string `json:"Ended,omitempty"`
	// Error is set where a library could not be read at all — an unmounted
	// volume, most often. Reported rather than thrown away, because "the drive
	// is not there" is the answer somebody is looking for.
	Error string `json:"Error,omitempty"`
}

var progress struct {
	sync.Mutex
	current Progress
}

// Snapshot is the progress as it stands, for the status endpoint.
func Snapshot() Progress {
	progress.Lock()
	defer progress.Unlock()
	return progress.current
}

func update(change func(*Progress)) {
	progress.Lock()
	defer progress.Unlock()
	change(&progress.current)
}

// Root is one library to scan.
type Root struct {
	LibraryID string
	Path      string
	Name      string
}

// AfterScan is called once a pass has finished, with what it added.
//
// The naming pass hangs off this rather than being called by the same button:
// what a scan finds is exactly what has no description and no artwork, so the
// two belong together — and a person who pressed Scan should not have to know
// that naming is a second step.
var AfterScan func(added int)

// Run scans every root in turn.
//
// Sequentially, and that is a decision rather than a simplification: the work is
// disk-bound on one volume, so two libraries at once is two sets of seeks
// competing for the same head, and the probe is a subprocess per file. One at a
// time is both faster here and the only version whose progress means anything.
func Run(db *store.Store, roots []Root, log *slog.Logger) {
	tool := FindFFprobe()
	if tool == "" {
		log.Info("scan: no ffprobe; runtimes and codecs will be left to the import")
	}
	scanner := &Scanner{Store: db, Log: log, FFprobe: tool}

	update(func(p *Progress) {
		*p = Progress{
			Running: true, Total: len(roots),
			Started: time.Now().UTC().Format(time.RFC3339),
		}
	})

	scanner.BeginPass()
	for index, root := range roots {
		update(func(p *Progress) {
			p.Index, p.Library = index+1, root.Name
		})

		// Counts carried from the libraries already done, so the running total
		// reported mid-library is the whole pass rather than this one.
		var done Progress
		update(func(p *Progress) { done = *p })

		result, err := scanner.ScanLibrary(root.LibraryID, root.Path, func(partial Result) {
			update(func(p *Progress) {
				p.Files = done.Files + partial.Files
				p.Added = done.Added + partial.Added
				p.Probed = done.Probed + partial.Probed
			})
		})
		if err != nil {
			log.Info("scan: skipped", "library", root.Name, "error", err)
			update(func(p *Progress) { p.Error = root.Name + ": " + err.Error() })
			continue
		}
		if isMusicLibrary(db, root.LibraryID) {
			if music, err := scanner.ScanMusic(root.LibraryID, root.Path); err != nil {
				log.Info("music scan: skipped", "library", root.Name, "error", err)
			} else {
				log.Info("music scanned", "library", root.Name, "tracks", music.Files,
					"added", music.Added, "moved", music.Moved, "removed", music.Removed)
				result.Added += music.Added
				result.Removed += music.Removed
				result.Moved += music.Moved
			}
		}
		log.Info("scanned", "library", root.Name, "files", result.Files,
			"added", result.Added, "probed", result.Probed, "missing", result.Missing,
			"moved", result.Moved, "removed", result.Removed)

		update(func(p *Progress) {
			p.Files = done.Files + result.Files
			p.Added = done.Added + result.Added
			p.Probed = done.Probed + result.Probed
			p.Missing = done.Missing + result.Missing
			p.Moved = done.Moved + result.Moved
			p.Removed = done.Removed + result.Removed
		})
	}
	// What every library left missing, now that all have been read. A file
	// moved between two libraries is found here, not in either.
	if moved, removed, missing := scanner.FinishPass(); moved+removed+missing > 0 {
		log.Info("scan: settled across libraries", "moved", moved, "removed", removed, "missing", missing)
		update(func(p *Progress) {
			p.Moved += moved
			p.Removed += removed
			p.Missing += missing
			p.Added -= moved
		})
	}

	AdoptOrphanFiles(db, roots, log)

	// The three the first scan got wrong, before the rules existed. Cheap and
	// idempotent — see Repair.
	repaired, err := Repair(db.DB, log)
	if err != nil {
		log.Error("scan: repair failed", "error", err)
	}
	// Files written with no parent, and the ones the import left with no
	// library. See relinkLooseFiles.
	// Matroska headers, for the openings and endings a release links to
	// rather than includes. See IndexSegments.
	if _, err := IndexSegments(db, 2000, log); err != nil {
		log.Error("scan: segment index failed", "error", err)
	}
	// Films the film rule made out of clips in plain folder libraries. See
	// unfoldFolderFilms; counted with the repairs so the naming pass follows.
	if unfolded, err := UnfoldFolderFilms(db.DB, roots, log); err != nil {
		log.Error("scan: unfold failed", "error", err)
	} else {
		repaired += unfolded
	}
	// Rows the client already has, changed under it. Recorded so a client
	// that syncs by new ids alone knows to read everything again — see
	// store.MetaRepairedAt.
	if repaired > 0 {
		if err := db.SetMeta(store.MetaRepairedAt, time.Now().UTC().Format(time.RFC3339)); err != nil {
			log.Error("scan: could not record repairs", "error", err)
		}
	}
	if linked, err := RelinkSeasonExtras(db.DB, roots, log); err != nil {
		log.Error("scan: season extras relink failed", "error", err)
	} else if linked > 0 {
		log.Info("scan: season extras relinked", "count", linked)
	}
	if linked, err := RelinkLooseFiles(db.DB, roots); err != nil {
		log.Error("scan: relink failed", "error", err)
	} else if linked > 0 {
		log.Info("scan: filed loose files under their folders", "count", linked)
	}

	// The parentage and numbering repairs the import runs, for the rows this
	// pass just wrote: a scanned episode has a series but a scanned *folder*
	// library has neither, and both are cheap to re-run.
	if err := store.LinkEpisodes(db.DB); err != nil {
		log.Error("scan: linking failed", "error", err)
	}
	if _, err := store.NumberEpisodes(db.DB); err != nil {
		log.Error("scan: numbering failed", "error", err)
	}

	// Counted across the whole catalogue rather than per root, which is the
	// number somebody actually wants. Per-library counting reported 31 while
	// 220 catalogued files were genuinely gone: a file whose path sits outside
	// any current library root — an old mount, a library since removed — was
	// never checked by the walk that would have missed it.
	missing, err := CountMissing(db)
	if err != nil {
		log.Error("scan: could not count missing", "error", err)
		missing = -1
	}

	unresolved, _ := db.UnresolvedLinks()
	update(func(p *Progress) {
		p.Running = false
		p.Library = ""
		p.UnresolvedLinks = unresolved
		if missing >= 0 {
			p.Missing = missing
		}
		p.Ended = time.Now().UTC().Format(time.RFC3339)
	})

	// Name what was found, without being asked — and what an earlier pass
	// left half-named. This used to run only when the scan added something,
	// on the reasoning that a scan that changed nothing had nothing to look
	// up; but the naming pass itself grows — episode titles were added to it
	// after most of the library had been through — and fifty-four episodes
	// sat under their filenames waiting for a new file to arrive. The pass
	// asks the database what is pending before it asks any provider, so a
	// run with nothing to do costs a few queries and no requests.
	if AfterScan != nil {
		AfterScan(Snapshot().Added + repaired)
	}
}
