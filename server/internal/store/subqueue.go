package store

import (
	"strings"
	"time"
)

// The subtitle queue: episodes waiting for a subtitle, fetched a few a day.
//
// OpenSubtitles caps downloads per day, so a season cannot be fetched in one
// go. It is queued instead, and a worker takes what the day allows. An
// episode that already has a subtitle in the language is never queued — the
// quota is too small to spend on a replacement nobody asked for.

// QueuedSubtitle is one episode waiting, or done.
type QueuedSubtitle struct {
	ItemID, Language, State, Note string
}

// SubtitleQueueCounts is the queue at a glance.
type SubtitleQueueCounts struct {
	Waiting, Done, Failed, DoneToday int
}

// QueueSubtitles adds the episodes of a series — one season, or all of them
// when seasonID is "" — that have no subtitle in the language. Returns how
// many were added.
func (s *Store) QueueSubtitles(seriesID, seasonID, language string) (int, error) {
	now := time.Now().UTC().Format(time.RFC3339)
	codes := LanguageCodes(language)
	placeholders := strings.TrimSuffix(strings.Repeat("?,", len(codes)), ",")
	args := []any{now, language, seriesID}
	filter := ""
	if seasonID != "" {
		filter = "AND COALESCE(ep.season_id, ep.parent_id) = ?"
		args = append(args, seasonID)
	}
	for _, c := range codes {
		args = append(args, c)
	}
	result, err := s.DB.Exec(`
		INSERT INTO subtitle_queue (item_id, language, added_at)
		SELECT ep.id, ?2, ?1 FROM item ep
		WHERE ep.type = 'Episode' AND ep.extra_type IS NULL AND ep.series_id = ?3
		  AND ep.path IS NOT NULL AND ep.path <> ''
		  `+filter+`
		  AND NOT EXISTS (SELECT 1 FROM stream st WHERE st.item_id = ep.id
		      AND st.type = 'Subtitle' AND lower(COALESCE(st.language, '')) IN (`+placeholders+`))
		ON CONFLICT DO NOTHING`, args...)
	if err != nil {
		return 0, err
	}
	n, _ := result.RowsAffected()
	return int(n), nil
}

// NextQueuedSubtitles is what the worker should fetch next, oldest first.
func (s *Store) NextQueuedSubtitles(limit int) ([]QueuedSubtitle, error) {
	rows, err := s.DB.Query(`
		SELECT item_id, language, state, note FROM subtitle_queue
		WHERE state = 'waiting' ORDER BY added_at, item_id LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []QueuedSubtitle
	for rows.Next() {
		var q QueuedSubtitle
		if err := rows.Scan(&q.ItemID, &q.Language, &q.State, &q.Note); err != nil {
			return nil, err
		}
		out = append(out, q)
	}
	return out, rows.Err()
}

// FinishQueuedSubtitle records what happened to one.
func (s *Store) FinishQueuedSubtitle(itemID, language, state, note string) error {
	_, err := s.DB.Exec(`
		UPDATE subtitle_queue SET state = ?, note = ?, done_at = ?
		WHERE item_id = ? AND language = ?`,
		state, note, time.Now().UTC().Format(time.RFC3339), itemID, language)
	return err
}

// SubtitleQueueStatus counts the queue; DoneToday is what today's quota spent.
func (s *Store) SubtitleQueueStatus() (SubtitleQueueCounts, error) {
	var c SubtitleQueueCounts
	today := time.Now().UTC().Format("2006-01-02")
	err := s.DB.QueryRow(`
		SELECT
		  COALESCE(SUM(state = 'waiting'), 0), COALESCE(SUM(state = 'done'), 0),
		  COALESCE(SUM(state = 'failed'), 0),
		  COALESCE(SUM(state IN ('done', 'failed') AND substr(COALESCE(done_at, ''), 1, 10) = ?), 0)
		FROM subtitle_queue`, today).Scan(&c.Waiting, &c.Done, &c.Failed, &c.DoneToday)
	return c, err
}

// LanguageCodes is a two-letter code and the three-letter forms a stream's
// language tag may carry for it, so "en" finds a track tagged "eng".
func LanguageCodes(code string) []string {
	code = strings.ToLower(strings.TrimSpace(code))
	three := map[string][]string{
		"en": {"eng"}, "ja": {"jpn"}, "fr": {"fre", "fra"}, "de": {"ger", "deu"},
		"es": {"spa"}, "it": {"ita"}, "pt": {"por"}, "ru": {"rus"}, "zh": {"chi", "zho"},
		"ko": {"kor"}, "nl": {"dut", "nld"}, "pl": {"pol"}, "sv": {"swe"}, "ar": {"ara"},
	}
	return append([]string{code}, three[code]...)
}

// QueueByShow is one show's line in the queue report.
type QueueByShow struct {
	Series                string
	Waiting, Done, Failed int
}

// SubtitleQueueByShow is the queue grouped by show, busiest first.
func (s *Store) SubtitleQueueByShow() ([]QueueByShow, error) {
	rows, err := s.DB.Query(`
		SELECT COALESCE(i.series_name, i.name),
		       COALESCE(SUM(q.state = 'waiting'), 0), COALESCE(SUM(q.state = 'done'), 0),
		       COALESCE(SUM(q.state = 'failed'), 0)
		FROM subtitle_queue q JOIN item i ON i.id = q.item_id
		GROUP BY 1 ORDER BY 2 DESC, 1`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []QueueByShow
	for rows.Next() {
		var q QueueByShow
		if err := rows.Scan(&q.Series, &q.Waiting, &q.Done, &q.Failed); err != nil {
			return nil, err
		}
		out = append(out, q)
	}
	return out, rows.Err()
}

// RetryFailedSubtitles puts every failed entry back in the queue. Returns how
// many: a subtitle the provider lacked last week may be there now.
func (s *Store) RetryFailedSubtitles() (int, error) {
	result, err := s.DB.Exec(`UPDATE subtitle_queue SET state = 'waiting', note = '', done_at = NULL WHERE state = 'failed'`)
	if err != nil {
		return 0, err
	}
	n, _ := result.RowsAffected()
	return int(n), nil
}
