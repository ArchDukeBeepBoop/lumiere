package store

import "sync"

// A remembered Next Up.
//
// The query walks every episode in the library — about 200 ms on forty
// thousand — and the home screen asked on every rebuild although the answer
// only moves when watch state or the episode list does. It is kept against a
// fingerprint of both, read in a few milliseconds: any write anywhere, by any
// part of the server, changes the fingerprint, so a stale answer cannot be
// served however the change was made.

type nextUpMemo struct {
	mu      sync.Mutex
	entries map[string][]Item
}

var nextUpCache = &nextUpMemo{entries: map[string][]Item{}}

func (m *nextUpMemo) get(key string) ([]Item, bool) {
	m.mu.Lock()
	defer m.mu.Unlock()
	items, ok := m.entries[key]
	return items, ok
}

func (m *nextUpMemo) put(key string, items []Item) {
	m.mu.Lock()
	defer m.mu.Unlock()
	// Old fingerprints are worthless once a newer one exists; a handful of
	// keys at most (one per series asked about), so dropping them is enough.
	if len(m.entries) > 64 {
		m.entries = map[string][]Item{}
	}
	m.entries[key] = items
}

// nextUpFingerprint changes whenever anything Next Up reads could have: the
// watch state's size and newest change, and the item table's size and newest
// row. "" when it cannot be read, which disables the memo.
func (s *Store) nextUpFingerprint() string {
	var fp string
	err := s.DB.QueryRow(`
		SELECT (SELECT count(*) || ':' || COALESCE(max(updated_at), '') FROM user_data)
		    || '|' ||
		       (SELECT count(*) || ':' || COALESCE(max(rowid), 0) FROM item)`).Scan(&fp)
	if err != nil {
		return ""
	}
	return fp
}

// ChangeMarker is the same fingerprint, for clients deciding whether a sync
// has anything to find. Two counts and two maxima: cheap enough to poll.
func (s *Store) ChangeMarker() string { return s.nextUpFingerprint() }
