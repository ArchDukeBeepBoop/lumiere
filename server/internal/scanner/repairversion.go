package scanner

import (
	"log/slog"
	"strconv"
	"time"

	"lumiere-server/internal/store"
)

// RepairVersion is bumped whenever a step is added to Repair. A server that
// starts on a database last repaired by an older set runs the pass once, at
// once, instead of waiting for the next scan — which only comes when the app
// syncs, and so a fix could sit installed and unapplied for days.
//
//	1  seating episodes that had no season (seat.go)
const RepairVersion = 4

const metaRepairVersion = "repair_version"

// RepairIfNew runs Repair in the background when this build's repairs have
// not yet run on this database, and records that they have. Changes are
// announced to the app the way a scan's are, so it re-reads what moved.
func RepairIfNew(db *store.Store, log *slog.Logger) {
	done, _ := db.Meta(metaRepairVersion)
	if n, err := strconv.Atoi(done); err == nil && n >= RepairVersion {
		return
	}
	go func() {
		changed, err := Repair(db.DB, log)
		if err != nil {
			log.Error("startup repair failed", "error", err)
			return
		}
		if changed > 0 {
			db.SetMeta(store.MetaRepairedAt, time.Now().UTC().Format(time.RFC3339))
		}
		db.SetMeta(metaRepairVersion, strconv.Itoa(RepairVersion))
		log.Info("startup repair complete", "version", RepairVersion, "changed", changed)
	}()
}

// RepairAfterImport runs the repair pass after a Jellyfin re-import, which
// writes back the rows the pass had fixed. See importer.WatchJellyfin.
func RepairAfterImport(db *store.Store, log *slog.Logger) {
	changed, err := Repair(db.DB, log)
	if err != nil {
		log.Error("repair after import failed", "error", err)
		return
	}
	// No repaired_at stamp: that sends every client into a full re-read, and
	// what this repairs is what the import undid moments ago — the state
	// clients already hold.
	log.Info("repair after import", "changed", changed)
}
