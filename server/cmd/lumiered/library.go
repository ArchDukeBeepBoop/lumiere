package main

import (
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"lumiere-server/internal/config"
	"lumiere-server/internal/store"
)

// commit is stamped by LumiereControl's bundle script; "dev" from go run.
var commit = "dev"

// outliveTheController keeps the server serving when LumiereControl, whose
// pipe is this process's stdout and stderr, goes away. Go exits on SIGPIPE from
// a write to fd 1 or 2 unless the signal is handled; ignored, the write just
// fails and logfile.Tee carries on with the file. The television does not care
// whether a menu bar app is alive, and the next LumiereControl adopts this
// process rather than starting a second.
func outliveTheController() { signal.Ignore(syscall.SIGPIPE) }

// openLibrary opens the database, or refuses to when it has gone missing.
//
// The order is the point. Old backups move out first, so they count as
// evidence; the check runs before store.Open, which would otherwise create
// an empty database in the lost one's place; and the emptied-file check runs
// after, for the file an older server already made. A refusal exits with
// store.ExitLibraryMissing so the menu can offer Restore or Start Fresh.
func openLibrary(cfg *config.Config, log *slog.Logger) *store.Store {
	log.Info("starting", "commit", commit, "pid", os.Getpid(), "parent", os.Getppid())
	if moved, err := store.MoveOldBackups(cfg.DataDir, cfg.BackupDir); err != nil {
		log.Warn("could not move old backups out of the data folder", "error", err)
	} else if moved > 0 {
		log.Info("backups moved out of the data folder", "count", moved, "to", cfg.BackupDir)
	}
	places := store.BackupPlaces{Dir: cfg.BackupDir, Mirror: cfg.BackupMirror}
	if cfg.StartFresh {
		log.Warn("starting with a new library, as asked")
		store.ForgetWitness(cfg.Witness)
	} else if err := store.CheckLibraryPresent(cfg.DataDir, cfg.Witness, places); err != nil {
		log.Error(err.Error())
		os.Exit(store.ExitLibraryMissing)
	}

	db, err := store.Open(cfg.DataDir)
	if err != nil {
		log.Error("cannot open the library database", "error", err)
		os.Exit(1)
	}
	if !cfg.StartFresh {
		if err := db.CheckNotEmptied(cfg.DataDir, cfg.Witness); err != nil {
			log.Error(err.Error())
			db.Close()
			os.Exit(store.ExitLibraryMissing)
		}
	}
	db.KeepBackedUp(places, log)
	useCacheFolder(db, cfg, log)
	return db
}

// keepWitness records the library now and every six hours, so the witness
// is never more than a few hours behind what it vouches for.
func keepWitness(db *store.Store, cfg config.Config, serverID string, log *slog.Logger) {
	record := func() {
		if err := db.RecordWitness(cfg.Witness, serverID); err != nil {
			log.Warn("could not record the library witness", "error", err)
		}
	}
	record()
	go func() {
		for range time.Tick(6 * time.Hour) {
			record()
		}
	}()
}

// live is GET /health/live: the process can answer, nothing more. No lock,
// no database, no disk, so a busy library can never make the server look
// dead to the thing that restarts it. Readiness is a different question and
// is never a reason to kill.
func live(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusNoContent)
}
