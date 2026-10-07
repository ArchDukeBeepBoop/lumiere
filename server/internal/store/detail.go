package store

import "database/sql"

// The detail read: everything a list deliberately leaves out.
//
// Kept separate from hydrate() because the cost is different by two orders of
// magnitude. A 200-row page of episodes must not load 200 items' worth of
// streams, chapters and cast — the capture confirms no list response carries
// MediaSources at all — while a detail page is one item and can afford all of
// it.

type Stream struct {
	Index                     int
	Type, Codec               string
	Language, Title, Display  string
	IsDefault, IsForced       bool
	IsExternal                bool
	Width, Height, BitDepth   *int
	Profile                   string
	VideoRange, VideoRangeTyp string
	DvProfile, DvLevel        *int
	AvgFrameRate, FrameRate   *float64
	Channels, SampleRate      *int
	ChannelLayout             string
	BitRate                   *int
	Path                      string
}

type Chapter struct {
	StartTicks int64
	Name       string
	ImagePath  string
}

type Credit struct {
	PersonID, Name, Role, Type string
}

// Streams returns every track on an item, in file order.
func (s *Store) Streams(itemID string) ([]Stream, error) {
	rows, err := s.DB.Query(`
		SELECT idx, type, codec, language, title, display_title,
		       is_default, is_forced, is_external, width, height, bit_depth,
		       profile, video_range, video_range_type, dv_profile, dv_level,
		       average_frame_rate, real_frame_rate, channels, sample_rate,
		       channel_layout, bit_rate, path
		FROM stream WHERE item_id = ? ORDER BY idx`, itemID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Stream
	for rows.Next() {
		var st Stream
		var codec, language, title, display sql.NullString
		var isDefault, isForced, isExternal sql.NullBool
		var width, height, bitDepth sql.NullInt64
		var profile, videoRange, rangeType sql.NullString
		var dvProfile, dvLevel sql.NullInt64
		var avgRate, realRate sql.NullFloat64
		var channels, sampleRate, bitRate sql.NullInt64
		var layout, path sql.NullString

		if err := rows.Scan(&st.Index, &st.Type, &codec, &language, &title, &display,
			&isDefault, &isForced, &isExternal, &width, &height, &bitDepth,
			&profile, &videoRange, &rangeType, &dvProfile, &dvLevel,
			&avgRate, &realRate, &channels, &sampleRate, &layout, &bitRate,
			&path); err != nil {
			return nil, err
		}
		st.Codec, st.Language = codec.String, language.String
		st.Title, st.Display = title.String, display.String
		st.IsDefault, st.IsForced = isDefault.Bool, isForced.Bool
		st.IsExternal = isExternal.Bool
		st.Width, st.Height, st.BitDepth = intPtr(width), intPtr(height), intPtr(bitDepth)
		st.Profile = profile.String
		st.VideoRange, st.VideoRangeTyp = videoRange.String, rangeType.String
		st.DvProfile, st.DvLevel = intPtr(dvProfile), intPtr(dvLevel)
		st.AvgFrameRate, st.FrameRate = floatPtr(avgRate), floatPtr(realRate)
		st.Channels, st.SampleRate = intPtr(channels), intPtr(sampleRate)
		st.ChannelLayout, st.BitRate = layout.String, intPtr(bitRate)
		st.Path = path.String
		out = append(out, st)
	}
	return out, rows.Err()
}

func (s *Store) Chapters(itemID string) ([]Chapter, error) {
	rows, err := s.DB.Query(
		`SELECT start_ticks, name, image_path FROM chapter
		 WHERE item_id = ? ORDER BY idx`, itemID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Chapter
	for rows.Next() {
		var c Chapter
		var name, image sql.NullString
		if err := rows.Scan(&c.StartTicks, &name, &image); err != nil {
			return nil, err
		}
		c.Name, c.ImagePath = name.String, image.String
		out = append(out, c)
	}
	return out, rows.Err()
}

// Credits returns the cast and crew, in Jellyfin's own sort order.
//
// sort_order is the billing order someone curated; falling back to the name
// would put the voice of a background character above the lead.
func (s *Store) Credits(itemID string) ([]Credit, error) {
	rows, err := s.DB.Query(
		`SELECT person_id, name, role, type FROM person
		 WHERE item_id = ?
		 ORDER BY COALESCE(sort_order, 9999), name`, itemID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Credit
	for rows.Next() {
		var c Credit
		if err := rows.Scan(&c.PersonID, &c.Name, &c.Role, &c.Type); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// PrimaryTags returns the Primary image tag for a set of ids, for cast
// portraits — one query rather than one per person.
func (s *Store) PrimaryTags(ids []string) (map[string]string, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	rows, err := s.DB.Query(
		`SELECT item_id, tag FROM image
		 WHERE kind = 'Primary' AND idx = 0 AND item_id IN (`+placeholders(len(ids))+`)`,
		args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]string{}
	for rows.Next() {
		var id, tag string
		if err := rows.Scan(&id, &tag); err != nil {
			return nil, err
		}
		out[id] = tag
	}
	return out, rows.Err()
}

func floatPtr(f sql.NullFloat64) *float64 {
	if !f.Valid {
		return nil
	}
	return &f.Float64
}
