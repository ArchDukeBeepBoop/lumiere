// Command lumiered is the Lumiere media server, speaking the API the Lumiere apps use.
//
// It implements the endpoints in LUMIERE_API_SPEC.md §8's load-bearing list and
// nothing else. Everything it does not implement answers 404 deliberately.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"lumiere-server/internal/api"
	"lumiere-server/internal/config"
	"lumiere-server/internal/logfile"
	"lumiere-server/internal/media"
	"lumiere-server/internal/scanner"
	"lumiere-server/internal/store"
)

func main() {
	cfg := config.Load()
	log := slog.New(slog.NewTextHandler(logfile.Tee(os.Stderr, cfg.DataDir), &slog.HandlerOptions{Level: slog.LevelInfo}))

	db, err := store.Open(cfg.DataDir)
	if err != nil {
		log.Error("cannot open the library database", "error", err)
		os.Exit(1)
	}
	db.KeepBackedUp(cfg.DataDir, log)
	scanner.RepairIfNew(db, log)
	defer db.Close()

	identity, err := api.ResolveIdentity(cfg.DataDir, cfg.Addr)
	if err != nil {
		log.Error("cannot establish server identity", "error", err)
		os.Exit(1)
	}
	if identity.ServerID == "" {
		// Worth failing loudly rather than serving: a null Id makes every client
		// reject the address, and it would look like a network fault.
		log.Error("no server id; clients will refuse this address")
		os.Exit(1)
	}
	log.Info("identity", "id", identity.ServerID, "name", identity.ServerName)

	system := api.SystemHandler{Identity: identity}
	auth := api.AuthHandler{Store: db, Identity: identity, Log: log}
	guard := api.Auth{Store: db}

	mux := http.NewServeMux()

	// Unauthenticated by necessity — reachable before a token; kept this short.
	mux.HandleFunc("GET /System/Info/Public", system.PublicInfo)
	mux.HandleFunc("POST /Users/AuthenticateByName", auth.AuthenticateByName)
	mux.HandleFunc("GET /Users/Public", auth.PublicUsers)
	mux.HandleFunc("GET /QuickConnect/Enabled", auth.QuickConnectEnabled)
	// The first run: whether an account is needed, and making it.
	mux.HandleFunc("GET /Lumiere/Setup", auth.Setup)
	mux.HandleFunc("POST /Lumiere/Setup/Account", auth.CreateAccount)

	// Everything else needs a token.
	imageCache := &media.ImageCache{
		Dir:      filepath.Join(cfg.DataDir, "cache", "images"),
		MaxBytes: cfg.ImageCacheMax,
	}
	// Sweep once at startup: the cap may have been lowered since the last run,
	// and nothing else would notice until enough traffic arrived to trigger it.
	if err := imageCache.Prune(); err != nil {
		log.Warn("could not sweep the image cache", "error", err)
	}

	items := api.ItemsHandler{Store: db, Identity: identity, Log: log}
	images := api.ImagesHandler{
		Store: db, Log: log,
		Cache: imageCache,
	}

	authed := http.NewServeMux()
	authed.HandleFunc("GET /Users/Me", auth.CurrentUser)
	authed.HandleFunc("GET /UserViews", items.UserViews)
	authed.HandleFunc("GET /Items", items.Items)
	// The legacy per-user path, which is the only one Lumiere uses for detail.
	authed.HandleFunc("GET /Users/{userId}/Items/{id}", items.ItemDetail)
	authed.HandleFunc("GET /Users/{userId}/Items/{id}/SpecialFeatures", items.SpecialFeatures)
	authed.HandleFunc("GET /Shows/{seriesId}/Seasons", items.Seasons)
	authed.HandleFunc("GET /Shows/{seriesId}/Episodes", items.Episodes)
	authed.HandleFunc("GET /Shows/NextUp", items.NextUp)
	authed.HandleFunc("GET /Items/{id}/Similar", items.Similar)
	// Load-bearing per spec §8, and belonging to no batch in the plan — they
	// fell through the gap between Batches 3 and 5. An empty Continue Watching
	// shelf is exactly the error state this batch exists to remove.
	authed.HandleFunc("GET /UserItems/Resume", items.Resume)
	authed.HandleFunc("GET /Items/Latest", items.Latest)
	api.HealthHandler{Store: db, Log: log}.Register(authed)
	// The server's own naming pass — the last thing Jellyfin was needed for.
	meta := &api.MetadataHandler{
		Store:    db,
		DataDir:  cfg.DataDir,
		ImageDir: filepath.Join(cfg.DataDir, "cache", "images"),
		Log:      log,
	}
	authed.HandleFunc("GET /Metadata/Status", meta.Status)
	authed.HandleFunc("POST /Metadata/Key", meta.SetKey)

	// Subtitles the library does not have, and making them land on the line.
	// See api.SubtitleHandler.
	api.SubtitleHandler{Store: db, DataDir: cfg.DataDir, Log: log}.Register(authed)
	authed.HandleFunc("POST /Metadata/Run", meta.Run)
	authed.HandleFunc("POST /Metadata/Frames", meta.Frames)
	// TMDB's other episode orders, chosen per show. See metadata/episodegroups.go.
	authed.HandleFunc("GET /Shows/{seriesId}/EpisodeGroups", meta.EpisodeGroups)
	authed.HandleFunc("POST /Shows/{seriesId}/EpisodeGroup", meta.SetEpisodeGroup)

	// A scan that finds something names it, without a second press (AfterScan).
	scanner.AfterScan = func(added int) {
		if meta.Start() {
			log.Info("naming what the scan found", "items", added)
			return
		}
		// No key, or a pass already running: the files still get pictures.
		meta.FramesOnly()
	}
	// And once at start, for what the last run left pending — a server that
	// was stopped mid-pass, or one whose naming pass has since learned to
	// fill a field it used to leave alone.
	go func() {
		time.Sleep(20 * time.Second)
		if meta.Start() {
			log.Info("naming what was left pending")
		}
	}()

	// The sync panel's Scan button. See api.RefreshHandler.
	refresh := &api.RefreshHandler{Store: db, Log: log}
	authed.HandleFunc("POST /Library/Refresh", refresh.Refresh)
	authed.HandleFunc("GET /Library/Refresh/Status", refresh.Status)
	registerSchedule(authed, db, cfg, refresh, log)
	api.LibrariesHandler{Store: db, Refresh: refresh, Log: log}.Register(authed)
	authed.HandleFunc("POST /Lumiere/Account/Password", auth.ChangePassword)
	registerChanges(authed, db, log)

	authed.HandleFunc("GET /Artists", items.Artists)
	authed.HandleFunc("GET /Artists/AlbumArtists", items.Artists)
	authed.HandleFunc("GET /MusicGenres", items.MusicGenres)
	authed.HandleFunc("GET /Genres", items.Genres)
	authed.HandleFunc("GET /MediaSegments/{id}", items.MediaSegments)
	authed.HandleFunc("GET /ScheduledTasks", items.ScheduledTasks)

	watch := api.WatchHandler{Store: db, Log: log}
	// Start, progress and stopped. Stopped is the one that persists a resume
	// position; the other two keep Continue Watching honest while playing.
	authed.HandleFunc("POST /Sessions/Playing", watch.Playing(false))
	authed.HandleFunc("POST /Sessions/Playing/Progress", watch.Playing(false))
	authed.HandleFunc("POST /Sessions/Playing/Stopped", watch.Playing(true))
	authed.HandleFunc("POST /UserPlayedItems/{itemId}", watch.Played(true))
	authed.HandleFunc("DELETE /UserPlayedItems/{itemId}", watch.Played(false))
	authed.HandleFunc("POST /UserFavoriteItems/{itemId}", watch.Favorite(true))
	authed.HandleFunc("DELETE /UserFavoriteItems/{itemId}", watch.Favorite(false))

	playback := api.PlaybackHandler{Store: db, Identity: identity, Log: log}
	authed.HandleFunc("POST /Items/{id}/PlaybackInfo", playback.PlaybackInfo)
	authed.HandleFunc("GET /Videos/{id}/stream", playback.Stream)
	// Music takes a different route to the same job. 2,301 audio items here, and
	// without this every one of them 404s rather than playing.
	authed.HandleFunc("GET /Audio/{id}/universal", playback.Stream)
	authed.HandleFunc("GET /Audio/{id}/stream", playback.Stream)
	// The last segment is a whole wildcard because ServeMux requires it to be:
	// "Stream.{ext}" is not a legal pattern, and asking for it panics at
	// startup. The extension is advisory anyway — this server does not convert
	// between subtitle formats.
	authed.HandleFunc("GET /Videos/{id}/{mediaSourceId}/Subtitles/{index}/{filename}",
		playback.Subtitle)
	// No encoder, by design. Named routes rather than a catch-all so the log
	// says which one was asked for.
	authed.HandleFunc("GET /Videos/{id}/stream.mp4", playback.NoEncoder)
	authed.HandleFunc("GET /Videos/{id}/main.m3u8", playback.NoEncoder)
	authed.HandleFunc("GET /Videos/{id}/master.m3u8", playback.NoEncoder)
	authed.HandleFunc("GET /Items/{id}/Images/{kind}", images.Image)
	authed.HandleFunc("GET /Items/{id}/Images/{kind}/{index}", images.Image)

	// Identify. Lumiere searches the provider itself with the user's own key and
	// posts the answer here; see api.IdentifyHandler for why nothing in this
	// server needs a key of its own.
	identify := api.IdentifyHandler{
		Store:    db,
		DataDir:  cfg.DataDir,
		ImageDir: filepath.Join(cfg.DataDir, "cache", "images"),
		Log:      log,
	}
	authed.HandleFunc("POST /Items/RemoteSearch/Apply/{itemId}", identify.Apply)
	remoteSearch := api.RemoteSearchHandler{Store: db, DataDir: cfg.DataDir, Log: log}
	authed.HandleFunc("POST /Items/RemoteSearch/Movie", remoteSearch.Search(false))
	authed.HandleFunc("POST /Items/RemoteSearch/Series", remoteSearch.Search(true))

	// The Edit Metadata sheet. Jellyfin's contract: the whole item, posted
	// back with the edited keys changed. See api.EditHandler.
	edit := api.EditHandler{Store: db, Log: log}
	authed.HandleFunc("POST /Items/{id}", edit.Edit)

	registerContainers(authed, db, items, cfg.DataDir, log)
	registerPrivate(authed, db)

	// Taking content out. See api.RemovalHandler.
	removal := api.RemovalHandler{Store: db, Log: log}
	authed.HandleFunc("GET /Items/Removed", removal.Removed)
	linked := api.LinkedHandler{Store: db, Log: log}
	authed.HandleFunc("GET /Items/{id}/LinkedChapters", linked.LinkedChapters)
	authed.HandleFunc("DELETE /Items/{id}", removal.Delete)
	authed.HandleFunc("POST /Items/{id}/Restore", removal.Restore)
	authed.HandleFunc("POST /Items/Untrash", removal.Untrash)
	itemRefresh := api.ItemRefreshHandler{
		Store: db, DataDir: cfg.DataDir,
		ImageDir: filepath.Join(cfg.DataDir, "cache", "images"), Log: log,
	}
	authed.HandleFunc("POST /Items/{id}/Refresh", itemRefresh.Refresh)

	// Choosing, replacing and removing a picture. See api.ArtworkHandler for
	// why none of this could be answered before the server held a key.
	artwork := api.ArtworkHandler{
		Store:    db,
		DataDir:  cfg.DataDir,
		ImageDir: filepath.Join(cfg.DataDir, "cache", "images"),
		Log:      log,
	}
	authed.HandleFunc("GET /Items/{id}/RemoteImages", artwork.Remote)
	authed.HandleFunc("POST /Items/{id}/RemoteImages/Download", artwork.Download)
	authed.HandleFunc("POST /Items/{id}/Images/{kind}", artwork.Upload)
	authed.HandleFunc("DELETE /Items/{id}/Images/{kind}", artwork.Delete)

	// Episode stills, on the same terms: the client looks them up with its own
	// TMDB key and names the pictures; this fetches and files them, and only for
	// episodes that have none.
	episodeImages := api.EpisodeImagesHandler{
		Store:    db,
		ImageDir: filepath.Join(cfg.DataDir, "cache", "images"),
		Log:      log,
	}
	authed.HandleFunc("GET /Shows/{seriesId}/EpisodeImages/Pending", episodeImages.Pending)
	authed.HandleFunc("POST /Shows/{seriesId}/EpisodeImages", episodeImages.Apply)

	mux.Handle("/", guard.RequireAuth(authed))

	server := &http.Server{
		Addr: cfg.Addr,
		// Outermost after the log, so a rebound name is refused before any
		// handler — auth included — gets to look at the request. See
		// `api.LocalOnly`.
		Handler: logging(log, api.LocalOnly(cfg.Addr, mux)),
		// Deliberately no WriteTimeout: this server streams films. A write
		// deadline is the standard advice and it would cut every playback at the
		// deadline. Read and idle timeouts still bound the cheap failure modes.
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	// Bind before announcing it, and before backgrounding anything.
	//
	// The obvious ListenAndServe in a goroutine logs "listening" and only then
	// discovers the port is taken — so a stale server from an earlier session
	// keeps answering while this one exits, and every request goes to the old
	// binary. That is precisely how it failed once here: an hour-old process
	// served 404s for routes this build had, and the log said "listening".
	listener, err := net.Listen("tcp", cfg.Addr)
	if err != nil {
		log.Error("cannot bind", "addr", cfg.Addr, "error", err)
		os.Exit(1)
	}
	log.Info("listening", "addr", cfg.Addr)
	startNetwork(logging(log, mux), cfg, db, identity, log)

	go func() {
		if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("serve failed", "error", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	<-stop

	// A short drain, not a long one: an interrupted playback is a resumed
	// playback, and nothing here is a transaction worth waiting on.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = server.Shutdown(ctx)
	log.Info("stopped")
}
