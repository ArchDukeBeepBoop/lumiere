-- The shape this server serves, not a transcription of Jellyfin's.
--
-- Every column here exists because LUMIERE_API_SPEC.md §5 says the client
-- decodes it. Jellyfin's BaseItems has 72 columns; Lumiere reads about 30 of
-- them, and carrying the rest would be storage that can only ever go stale.

CREATE TABLE IF NOT EXISTS item (
    id                  TEXT PRIMARY KEY NOT NULL,  -- 32 hex, dashes stripped
    type                TEXT NOT NULL,              -- Movie, Series, Episode, ...
    name                TEXT NOT NULL,
    sort_name           TEXT,
    original_title      TEXT,
    overview            TEXT,
    tagline             TEXT,

    parent_id           TEXT,
    library_id          TEXT,                       -- Jellyfin's TopParentId
    series_id           TEXT,
    series_name         TEXT,
    season_id           TEXT,
    season_name         TEXT,
    index_number        INTEGER,
    parent_index_number INTEGER,

    production_year     INTEGER,
    premiere_date       TEXT,
    date_created        TEXT,                       -- every Latest shelf sorts on this
    official_rating     TEXT,
    community_rating    REAL,
    critic_rating       REAL,
    runtime_ticks       INTEGER,

    container           TEXT,
    path                TEXT,                       -- absolute; a key in folder libraries
    size                INTEGER,
    total_bitrate       INTEGER,

    is_folder           INTEGER NOT NULL DEFAULT 0,
    collection_type     TEXT,                       -- libraries only; NULL = folder library
    extra_type          TEXT,

    album               TEXT,
    album_artist        TEXT,
    -- Pipe-separated, as Jellyfin stores it. A join table for two columns that
    -- are only ever read together would be three queries to draw one row.
    artists             TEXT,
    album_id            TEXT
);

CREATE INDEX IF NOT EXISTS item_parent   ON item(parent_id);
CREATE INDEX IF NOT EXISTS item_library  ON item(library_id, sort_name);
CREATE INDEX IF NOT EXISTS item_series   ON item(series_id, parent_index_number, index_number);
CREATE INDEX IF NOT EXISTS item_type     ON item(type);
CREATE INDEX IF NOT EXISTS item_created  ON item(date_created);
CREATE INDEX IF NOT EXISTS item_path     ON item(path);

-- Artwork lives in Jellyfin's metadata tree; this is the index into it.
-- `tag` is a content address: the client caches on it forever, so it must change
-- when the picture does and never otherwise. See spec §7.1.
CREATE TABLE IF NOT EXISTS image (
    item_id   TEXT NOT NULL,
    kind      TEXT NOT NULL,       -- Primary, Backdrop, Thumb, Logo, Banner
    idx       INTEGER NOT NULL DEFAULT 0,
    path      TEXT NOT NULL,
    tag       TEXT NOT NULL,
    width     INTEGER,
    height    INTEGER,
    blurhash  TEXT,
    PRIMARY KEY (item_id, kind, idx)
);

-- What PlaybackInfo returns and what the client's whole routing decision is made
-- from. Already probed by Jellyfin — 247,855 rows — so nothing here re-runs
-- ffprobe over 45,000 files.
CREATE TABLE IF NOT EXISTS stream (
    item_id           TEXT NOT NULL,
    idx               INTEGER NOT NULL,   -- Jellyfin's absolute StreamIndex
    type              TEXT NOT NULL,      -- Video, Audio, Subtitle, EmbeddedImage
    codec             TEXT,
    language          TEXT,
    title             TEXT,
    display_title     TEXT,
    is_default        INTEGER,
    is_forced         INTEGER,
    is_external       INTEGER,
    width             INTEGER,
    height            INTEGER,
    bit_depth         INTEGER,
    video_range       TEXT,
    video_range_type  TEXT,
    dv_profile        INTEGER,
    dv_level          INTEGER,
    profile           TEXT,
    average_frame_rate REAL,
    real_frame_rate   REAL,
    channels          INTEGER,
    sample_rate       INTEGER,
    channel_layout    TEXT,
    bit_rate          INTEGER,
    path              TEXT,               -- external subtitle files
    PRIMARY KEY (item_id, idx)
);

-- The only irreplaceable data in the system. 2,734 rows.
--
-- `source` records who last wrote a row: 'jellyfin' for anything the import
-- brought over, 'local' for anything this server wrote itself. A re-import must
-- be able to tell them apart — see importer.userdata.
CREATE TABLE IF NOT EXISTS user_data (
    item_id         TEXT PRIMARY KEY NOT NULL,
    played          INTEGER NOT NULL DEFAULT 0,
    play_count      INTEGER NOT NULL DEFAULT 0,
    position_ticks  INTEGER NOT NULL DEFAULT 0,
    is_favorite     INTEGER NOT NULL DEFAULT 0,
    last_played     TEXT,
    audio_index     INTEGER,
    subtitle_index  INTEGER,
    updated_at      TEXT NOT NULL,
    source          TEXT NOT NULL DEFAULT 'jellyfin'
);

CREATE INDEX IF NOT EXISTS user_data_played ON user_data(last_played DESC);

-- Genres, studios and tags, which Jellyfin keeps in ItemValues rather than on
-- the item. Kind is this server's word, not its enum: type 2 is Genre, 3 Studio,
-- 4 Tag, verified against the live database.
CREATE TABLE IF NOT EXISTS item_value (
    item_id TEXT NOT NULL,
    kind    TEXT NOT NULL,   -- genre, studio, tag
    value   TEXT NOT NULL,
    PRIMARY KEY (item_id, kind, value)
);

CREATE INDEX IF NOT EXISTS item_value_lookup ON item_value(kind, value);

CREATE TABLE IF NOT EXISTS person (
    item_id    TEXT NOT NULL,
    person_id  TEXT NOT NULL,
    name       TEXT NOT NULL,
    role       TEXT,
    type       TEXT,
    sort_order INTEGER,
    PRIMARY KEY (item_id, person_id, type, role)
);

CREATE TABLE IF NOT EXISTS chapter (
    item_id     TEXT NOT NULL,
    idx         INTEGER NOT NULL,
    start_ticks INTEGER NOT NULL,
    name        TEXT,
    image_path  TEXT,
    PRIMARY KEY (item_id, idx)
);

-- Intro Skipper's output, 75,414 rows. Cosmetic per the spec, and free to carry.
CREATE TABLE IF NOT EXISTS segment (
    item_id     TEXT NOT NULL,
    type        TEXT NOT NULL,   -- Intro, Outro, Recap, Preview, Commercial
    start_ticks INTEGER NOT NULL,
    end_ticks   INTEGER NOT NULL,
    PRIMARY KEY (item_id, type, start_ticks)
);

CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);

-- Batch 2. Accounts and tokens.
--
-- The password hash is Jellyfin's own, imported verbatim and never re-hashed:
-- the same password the user already types keeps working, and this server never
-- learns a plaintext it would then have to be trusted with.
CREATE TABLE IF NOT EXISTS account (
    id            TEXT PRIMARY KEY NOT NULL,  -- 32 hex, dashes stripped
    username      TEXT NOT NULL,
    -- Jellyfin's format: $PBKDF2-SHA512$iterations=N$SALTHEX$HASHHEX.
    -- NULL means the account has no password set, which is a valid Jellyfin
    -- state and must not silently become "any password works".
    password_hash TEXT,
    updated_at    TEXT NOT NULL
);

-- Tokens outlive the process on purpose.
--
-- Lumiere keeps its token in the keychain and never refreshes: the spec is
-- explicit that a token is valid until the server rejects it. Holding them in
-- memory would sign every user out on restart, which reads to the client as
-- exactly the same event as a stolen token.
CREATE TABLE IF NOT EXISTS token (
    token      TEXT PRIMARY KEY NOT NULL,
    account_id TEXT NOT NULL REFERENCES account(id),
    -- Device fields come from the MediaBrowser header. DeviceId is stable across
    -- launches (UserDefaults), so it is what a session record keys on.
    device_id  TEXT,
    device     TEXT,
    client     TEXT,
    version    TEXT,
    created_at TEXT NOT NULL,
    last_seen  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS token_by_device ON token(device_id);

-- Batch 3. Indexes for the read path.
--
-- The sync is 123 pages of LIMIT 200 with an OFFSET that grows to ~24,000, and
-- every page runs a COUNT(*) beside it for TotalRecordCount. Without an index
-- on the sort column that is a full scan and a sort of the whole table, per
-- page. These are the columns the WHERE and ORDER BY in store/items.go touch.
CREATE INDEX IF NOT EXISTS item_by_type ON item(type);
CREATE INDEX IF NOT EXISTS item_by_parent ON item(parent_id);
CREATE INDEX IF NOT EXISTS item_by_library ON item(library_id);
CREATE INDEX IF NOT EXISTS item_by_sort_name ON item(sort_name COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS item_by_date_created ON item(date_created);
CREATE INDEX IF NOT EXISTS item_by_series ON item(series_id);
CREATE INDEX IF NOT EXISTS item_by_season ON item(season_id);
CREATE INDEX IF NOT EXISTS image_by_item ON image(item_id);
CREATE INDEX IF NOT EXISTS item_value_by_item ON item_value(item_id);
CREATE INDEX IF NOT EXISTS person_by_item ON person(item_id);

-- Which physical folders back each library view.
--
-- Not cosmetic: a CollectionFolder's id is NOT the TopParentId of its contents.
-- Jellyfin gives every library a virtual CollectionFolder and one or more
-- physical Folder items beneath it, and it is the physical folder's id that
-- lands in every child's TopParentId. The link lives only in the Data blob, as
-- `PhysicalFolderIds`. Without this table, `/Items?ParentId=<library>` matches
-- nothing at all and every library reads as empty.
CREATE TABLE IF NOT EXISTS library_folder (
    view_id   TEXT NOT NULL,   -- the CollectionFolder the client asks for
    folder_id TEXT NOT NULL,   -- what its children actually carry as library_id
    PRIMARY KEY (view_id, folder_id)
);

-- The sync's index. Covers WHERE library_id = ? ORDER BY sort_name, name, id,
-- which is the exact shape of every page of a full sync. Without it SQLite
-- sorts the whole library into a temp B-tree per page — measured at 880ms on
-- the 25,237-item library, 127 times.
CREATE INDEX IF NOT EXISTS item_library_sorted
    ON item(library_id, sort_name COLLATE NOCASE, name COLLATE NOCASE, id);

-- Batch 7. Play sessions, so late reports can be ordered.
--
-- Lumiere queues progress reports when the server is unreachable and replays
-- them on reconnect, so a report can arrive long after the moment it describes.
-- The reports carry no timestamp — only a PlaySessionId — so the only way to
-- tell a stale replay from a current one is to remember when each session was
-- first seen. Within a session the client replays in order; across sessions the
-- one that started later wins.
--
-- Rows are cheap and disposable: one per playback, and nothing reads them but
-- the ordering rule.
CREATE TABLE IF NOT EXISTS play_session (
    session_id TEXT PRIMARY KEY NOT NULL,
    item_id    TEXT NOT NULL,
    started_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS play_session_started ON play_session(started_at);

-- Which session last wrote a row, for the ordering rule above. Added as its own
-- statement rather than in the CREATE TABLE, because user_data already exists
-- on every installed copy of this server and its contents are the one thing
-- here that cannot be rebuilt.
ALTER TABLE user_data ADD COLUMN session_id TEXT;

-- The artists on a track, pipe-separated as Jellyfin stores them. Its own
-- statement for the same reason as the column above: item already exists on
-- every installed copy, so a column added to the CREATE TABLE would only ever
-- reach a database created from scratch.
ALTER TABLE item ADD COLUMN artists TEXT;

-- Membership of a collection or a playlist. A film is filed under its folder
-- by parent_id and can belong to any number of collections besides, so
-- membership is a link, not a parent. Jellyfin keeps this in its own table
-- and the import never carried it — every collection arrived empty.
CREATE TABLE IF NOT EXISTS link (
    parent_id TEXT NOT NULL,
    child_id  TEXT NOT NULL,
    position  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (parent_id, child_id)
);
CREATE INDEX IF NOT EXISTS link_by_child ON link(child_id);

-- Rows removed from the library but not from the disk. The same shape as
-- item, so a row moves across and back whole; a removed item is out of every
-- query by construction rather than by a filter each query has to remember.
-- The file is untouched and the row can be put back. See removal.go.
CREATE TABLE IF NOT EXISTS removed_item (
    id TEXT PRIMARY KEY NOT NULL,
    removed_at TEXT NOT NULL,
    -- Everything the item row held, as JSON, so the columns cannot drift
    -- from the table they came from.
    row TEXT NOT NULL
);

-- Matroska segment linking. A file's own segment UID, and — for an ordered
-- edition — the ranges it plays in order, some of them borrowed from another
-- segment by UID. Resolved at read time against mkv_segment; a link with no
-- match is a file the release expects beside the episode and does not find.
CREATE TABLE IF NOT EXISTS mkv_segment (
    item_id TEXT PRIMARY KEY NOT NULL,
    uid     TEXT NOT NULL,
    ordered INTEGER NOT NULL DEFAULT 0,
    read_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS mkv_segment_uid ON mkv_segment(uid);
CREATE TABLE IF NOT EXISTS mkv_link (
    item_id  TEXT NOT NULL,
    position INTEGER NOT NULL,
    start_ns INTEGER NOT NULL,
    end_ns   INTEGER NOT NULL,
    link_uid TEXT,
    title    TEXT,
    PRIMARY KEY (item_id, position)
);

-- Episodes waiting for a subtitle from the provider, fetched a few a day
-- within its quota. See store/subqueue.go.
CREATE TABLE IF NOT EXISTS subtitle_queue (
    item_id   TEXT NOT NULL,
    language  TEXT NOT NULL,
    added_at  TEXT NOT NULL,
    state     TEXT NOT NULL DEFAULT 'waiting',  -- waiting, done, failed
    note      TEXT NOT NULL DEFAULT '',
    done_at   TEXT,
    PRIMARY KEY (item_id, language)
);

-- Health findings the owner has said to leave alone: a show whose missing
-- episodes are skipped filler, say. See store/health_gaps.go.
CREATE TABLE IF NOT EXISTS health_dismissed (
    kind TEXT NOT NULL,
    key  TEXT NOT NULL,
    PRIMARY KEY (kind, key)
);

-- What a structural repair changed, so that repair alone can be undone
-- without restoring the whole database. See scanner/seat.go.
CREATE TABLE IF NOT EXISTS repair_log (
    step        TEXT NOT NULL,
    item_id     TEXT NOT NULL,
    season_id   TEXT,
    parent_id   TEXT,
    parent_index_number INTEGER,
    created     INTEGER NOT NULL DEFAULT 0,   -- 1: a row the repair made
    at          TEXT NOT NULL
);
