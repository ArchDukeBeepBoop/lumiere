# Lumiere Server — evolution plan

Written 2026-10-25, the morning the library database disappeared. Each phase
has an exit test: a phase is done when its test passes, not when its code is
written. Phases are ordered by risk to the one thing that cannot be rebuilt —
the watch history — and then by daily pain.

The practices are named with their source so each can be checked rather than
taken on trust: the 3-2-1 backup rule, Google SRE (golden signals, probes),
Kubernetes probe semantics, Apple's `SMAppService`/launchd guidance, SQLite's
WAL documentation, OWASP ASVS 4 Level 2, the Go team's tooling (`govulncheck`,
`-race`, fuzzing), RFC 9457 and RFC 9110, and Jellyfin, Plex and Infuse for what
a media server is expected to do.

---

## What happened on 2026-10-25

- Between 01:04 and 02:22 the files at the top of
  `~/Library/Application Support/LumiereServer/` — `library.db`, its WAL,
  `backups/`, `logs/`, `server-id` and the stored keys — were removed. `cache/`
  (142 MB of previews) was left, and was still being written until 02:22, so a
  server was running on the old, now-unlinked database the whole time.
- At 02:23 the server restarted, found no database, and **silently made a new
  empty one**: 0 items, 0 accounts, 0 sign-ins, a new server id. Every request
  from the Mac has been `401` since, because the token it holds names an account
  that no longer exists.
- The week of verified backups lived in the same folder and went with it. No
  Time Machine, no local snapshots.
- No Claude session ran anything in that window. The cause is still unknown.
- Recovery source: Lumiere's own cache, copied (integrity ok) to
  `~/Library/Application Support/LumiereRecovery-20261025/`: 51,892 items with
  paths, 1,098 watched, 236 in progress, 271 favourites.

Separately, and older: LumiereControl's watchdog SIGTERMs the server after a
**single** missed 2-second probe and never restarts it. Lumiere's launch burst
is exactly when a probe misses — the client log shows
`The network connection was lost` at launch after launch on 10-24.

---

## Phase 0 — Never lose the library again (now)

### 0.1 Recover what can be recovered — done 2026-10-25 (`internal/rebuild`)
1. Recreate the account and libraries (first-run setup), rescan.
2. A one-off recovery tool (`cmd/recover`, not committed) maps every row of the
   client cache to the new items **by file path**, and writes `played`,
   `playCount`, position, favourite and last-played into `user_data` in one
   transaction, after a backup. Paths, not ids: imported items kept Jellyfin's
   ids, new scans use `ItemID(path)`, so ids will not line up but paths will.
3. Report what could not be matched, by count only.

Lost for good unless a copy turns up: hand-typed titles and locks, collections
and themes, episode-order choices, subtitle offsets, the TMDB and
OpenSubtitles keys (re-enter in Settings), every device's sign-in.

### 0.2 Refuse to start on a missing library — done (`store/witness.go`, exit 3)
Industry rule: a data store that was there yesterday and is gone today is an
incident, not a first run (PostgreSQL refuses to start on a missing data
directory rather than running `initdb`).
- The server keeps a small **witness** file outside its data folder
  (`~/Library/Preferences/com.lumiere.server.witness`: server id, item count,
  last-seen time). If the witness says a library existed and `library.db` is
  missing or empty, the server **exits with a clear error** instead of creating
  one. First run is the only case that may create a database, and only when no
  witness exists.
- LumiereControl shows that error in the menu with two buttons: Restore Backup,
  or Start Fresh (with a confirmation that names what will be lost).

**Exit test.** A store test: delete the database with a witness present → the
server exits non-zero with the message; no witness → it creates one.

### 0.3 Backups that do not share the database's fate (3-2-1) — done; the menu's 48-hour warning is still to do
- Daily verified copies move **out of the data folder** to
  `~/Library/Application Support/LumiereServer Backups/` and, optionally, a second
  destination chosen in Settings (an external volume, iCloud Drive).
- A weekly copy is kept for 8 weeks beside the 7 dailies.
- The menu shows the age of the newest copy in *each* place, and turns red if any
  is over 48 hours old.

**Exit test.** Remove the data folder on a trial copy: Restore Backup brings the
library back with its watch state intact.

### 0.4 The watchdog — done (`ControlCore/Watchdog.swift`, `/health/live`)
Kubernetes probe semantics, launchd restart behaviour:
- A **liveness** route, `GET /health/live`, that touches no lock, no database and
  no disk. Readiness (`/health/ready`) is separate and never a reason to kill.
- Kill only after **3 consecutive** misses with a 5 s timeout, and only a process
  this app started; an adopted server is reported, never signalled.
- **Restart** after a kill or crash, with backoff (1, 2, 4 … 60 s; give up after
  5 in 10 minutes and say so in the menu and a notification).
- Every stop the controller causes is written into the server's log with its
  reason.

**Exit test.** A ControlCore test drives the policy with a fake clock and fake
probe results (1 miss → nothing; 3 → restart; 6 → gives up). Then replay the
client's real launch burst against a trial copy: zero restarts.

### 0.5 Logs that outlive a run — done (4 old copies, 10 MB; start line with commit and parent)
Keep the last 5 runs (`lumiered.log`, `.1` … `.4`, 10 MB each) — today's log
starts at 02:23 and everything before it is gone. Every run begins with one line:
version, commit, pid, parent process, database item count.

### 0.6 Explainable sign-in failures
- 401 bodies on Lumiere's routes say `expired`, `unknown-token` or
  `no-such-account` (RFC 9457 `type`), so the app can say "This server has no
  account for you — it may have been reset" instead of a connection error.
- The 90-day expiry gets a defined start: rows predating the rule get
  `last_seen = now` once, so the clock starts the day it shipped.

---

## Phase 1 — Supervision and operability

| Item | Practice | Exit test |
|---|---|---|
| Run the server as a **launchd agent** via `SMAppService.agent`, `KeepAlive` on crash. The controller becomes a view and a switch — reversing `ServerProcess`'s documented trade, because its cost (the server dies with the menu app, and only the menu app can revive it) is the 0.4 bug class. | Apple's supported way to keep a helper alive | Quit the controller: still serving. `kill -9` the server: back within 10 s |
| **Every background goroutine under one root `context`**, cancelled on SIGTERM, each wrapped in `recover` that logs the stack. A panic in a request is survived today; one in the scanner exits the process. | Go structured concurrency (`errgroup`) | A test panics a worker; the server keeps serving and logs it |
| **Request IDs and latency** on every log line; requests over 500 ms logged at Warn by route pattern, never by item name | SRE golden signals | `report.sh` lists the day's five slowest routes |
| **`/debug/vars` and `pprof`**, loopback only, behind a flag | Go `expvar`, `net/http/pprof` | A profile of the launch burst without a rebuild |
| **Build stamping** (commit + date via `-ldflags`) in `/System/Info` and Settings › About | Identifiable builds | About shows `git rev-parse HEAD` |

---

## Phase 2 — The database

The 60-second busy timeout is a symptom: writers queue behind a scanner that
holds a transaction for up to 15 s. SQLite's recommended shape removes the cause.

1. **One writer connection, a pool of readers.** `SetMaxOpenConns(1)` with
   `_txlock=immediate` on the write handle; a separate read-only pool for every
   GET. In WAL, readers never wait on the writer; writes queue in Go, visibly,
   instead of in SQLite's busy loop. Busy timeout back to 5 s.
2. **Short write transactions.** The scanner commits every ≤200 ms or 500 rows.
   Exit test: no write transaction over 250 ms in a full scan on the trial copy.
3. **Versioned migrations** (`PRAGMA user_version`, one numbered function each,
   in a transaction; refuse a database newer than the binary). Replaces the
   "tolerate `duplicate column name`" rule and the shape-sniffing passes that run
   on every start forever. Exit test: the trial migrates from 0 and from today.
4. **Housekeeping.** `PRAGMA optimize` nightly; `wal_checkpoint(TRUNCATE)` after
   the overnight passes.

---

## Phase 3 — The API as a contract

- **An OpenAPI document** for the routes Lumiere, the Android app and the TV use,
  with a test that fails when a handler's response stops matching it.
- **RFC 9457 problem+json** errors on Lumiere's own routes (Jellyfin-shaped routes
  keep their shape).
- **HTTP caching (RFC 9110).** `ETag`/`If-None-Match` on lists and shelves;
  `Cache-Control: immutable` on tagged images. The launch burst becomes a round of
  304s instead of a round of queries.
- **Deprecation policy** on `APILevel`: a level is announced in `/System/Info`
  one release before it is dropped.

---

## Phase 4 — Security, to ASVS Level 2

- `govulncheck ./...`, `go mod verify` and `go test -race` in the check script.
- Per-token rate limits on expensive routes (search, metadata runs, previews).
- Home-network mode refuses non-private source addresses outright.
- A security log (sign-ins, sign-outs, expiries, refused origins) separate from
  the request log, kept 90 days.

---

## Phase 5 — Performance budgets as tests

Lumiere holds itself to RAM budgets in its test suite; the server should hold
itself to latency budgets the same way, measured on the trial copy.

| Route | p95 budget |
|---|---|
| `/health/live` | 5 ms |
| `/UserViews`, `/Users/Me` | 20 ms |
| `/Items` page, `/Shows/NextUp`, `/UserItems/Resume` | 50 ms |
| Cached image | 10 ms |
| Client launch burst, end to end | 1.5 s |

---

## Phase 6 — What a media server is expected to do

1. **Intro and credits detection.** The app already asks `/MediaSegments/{id}`
   and logs "the server has no segment data". Audio fingerprinting across a
   season (the Jellyfin Intro Skipper approach), overnight, paused while playing.
2. **Sessions and remote control** — what is playing where, with pause and stop
   sent to that device; feeds a Now Playing tile in the menu.
3. **One scheduled-task registry** — every background pass with last run,
   duration, next run and Run Now, instead of separate timers.
4. **SyncPlay** — watching together across the TV and the Mac.
5. **Per-device playback profiles** — warn before choosing a file a device cannot
   direct-play (still never transcoding).

---

## Order

| Phase | Size | Depends on |
|---|---|---|
| 0 | 2–3 days; 0.1 first | — |
| 1 | 3–4 days | 0 |
| 2 | 4–5 days, trial-gated | 1 (metrics show before and after) |
| 3 | 3 days | 2 |
| 4 | 2 days | beside 3 |
| 5 | 2 days | 2, 3 |
| 6 | per feature | 1–5 |
