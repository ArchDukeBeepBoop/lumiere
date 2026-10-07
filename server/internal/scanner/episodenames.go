package scanner

import (
	"database/sql"
	"log/slog"

	"lumiere-server/internal/store"
)

// unblockEpisodeNames lets the naming pass look at episodes an older one
// wrote off.
//
// `provider:none` on an episode used to mean "TMDB listed no still for it",
// and the pending query reads it as "TMDB has nothing to say about it" —
// which was true of the only field that pass filled. Now the same request
// carries the title and the synopsis, and fifteen hundred episodes were
// excluded from ever receiving them, still wearing the filenames the scanner
// gave them.
//
// Cleared once, for the episodes that still show it. Recorded in meta so a
// show TMDB genuinely has nothing for is not re-asked on every scan
// thereafter.
func unblockEpisodeNames(db *sql.DB, log *slog.Logger) (int, error) {
	s := &store.Store{DB: db}
	done, err := s.Meta(metaEpisodeNamesUnblocked)
	if err != nil || done != "" {
		return 0, err
	}
	// Both marks. `episode:enriched` is the pass's own record that it has
	// answered for an episode, and an episode it answered before the rename
	// rule could see past a numbered filename is one it must answer for
	// again — the title it fetched was never written.
	result, err := db.Exec(`
		DELETE FROM item_value
		WHERE kind IN ('provider:none', 'episode:enriched') AND item_id IN (
			SELECT i.id FROM item i
			WHERE i.type = 'Episode'
			  AND (i.name GLOB '* - [0-9]*x[0-9]* - *'
			       OR i.name GLOB '*[Ss][0-9][0-9]*[Ee][0-9][0-9]*'
			       OR i.path LIKE '%/' || i.name || '.%'
			       OR COALESCE(i.overview, '') = '')
		)`)
	if err != nil {
		return 0, err
	}
	cleared, _ := result.RowsAffected()
	if err := s.SetMeta(metaEpisodeNamesUnblocked, "done"); err != nil {
		return int(cleared), err
	}
	if cleared > 0 {
		log.Info("repair: episodes released for naming", "count", cleared)
	}
	return int(cleared), nil
}

const metaEpisodeNamesUnblocked = "episode_names_unblocked_v3"
