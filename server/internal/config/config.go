// Package config resolves where the server listens and what it reads.
package config

import (
	"flag"
	"os"
	"path/filepath"
)

// Config is the whole of the server's configuration. Flags only, no file: there
// is one deployment of this and it runs on one machine.
type Config struct {
	// Addr is loopback by design. The client runs on this machine, so a LAN
	// listener would be a threat model nobody asked for. See the build plan §1.
	Addr string

	// DataDir is where this server keeps its own database and image cache.
	DataDir string

	// ImageCacheMax bounds the resized-variant cache in bytes. The originals
	// are never copied, so this bounds the only thing this server writes that
	// can grow without limit.
	ImageCacheMax int64

	// BackupDir holds the daily copies — not inside DataDir, so whatever
	// empties one does not empty the other. BackupMirror is an optional second
	// folder, ideally on another disk. See store/backup.go.
	BackupDir, BackupMirror string

	// CacheDir holds the pictures and scrubbing previews — the server's
	// bulk, gigabytes where the database is megabytes — wherever the person
	// chose: the media drive, say. Empty is DataDir/cache. See cachedir.go.
	CacheDir string

	// Witness remembers that a library existed, outside both. StartFresh is
	// the one deliberate way past a missing library. See store/witness.go.
	Witness    string
	StartFresh bool
}

// Load reads the flags. Defaults are the values on the machine this was written
// for, so the binary runs correctly with no arguments.
func Load() Config {
	home, _ := os.UserHomeDir()

	var c Config
	flag.StringVar(&c.Addr, "addr", "127.0.0.1:8098",
		"address to listen on; loopback by design")
	flag.StringVar(&c.DataDir, "data",
		filepath.Join(home, "Library", "Application Support", "LumiereServer"),
		"where this server keeps its own database and caches")
	flag.Int64Var(&c.ImageCacheMax, "image-cache-max", 512<<20,
		"bytes of resized artwork to keep; originals are never copied")
	flag.StringVar(&c.BackupDir, "backups",
		filepath.Join(home, "Library", "Application Support", "LumiereServer Backups"),
		"where the daily verified copies of the database go")
	flag.StringVar(&c.BackupMirror, "backup-mirror", "",
		"a second folder for each copy, ideally on another disk; skipped when not attached")
	flag.StringVar(&c.CacheDir, "cache", "",
		"where pictures and scrubbing previews are kept; empty keeps them in the data folder")
	flag.StringVar(&c.Witness, "witness",
		filepath.Join(home, "Library", "Preferences", "com.lumiere.server.witness.json"),
		"the record that a library existed, kept apart from it")
	flag.BoolVar(&c.StartFresh, "start-fresh", false,
		"start with a new, empty library even though one existed; never the default")
	flag.Parse()

	return c
}
