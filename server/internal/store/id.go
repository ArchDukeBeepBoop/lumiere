package store

import "strings"

// NormalizeID turns Jellyfin's stored id into the one its API serves.
//
// The database keeps 36-character dashed GUIDs; every id on the wire — and
// every id Lumiere has cached against its 45,000 rows — is 32 lowercase hex
// characters with the dashes removed. Getting this wrong does not fail loudly:
// it produces a server whose ids simply never match anything the client knows.
// ZeroGUID is Jellyfin's way of writing "no id".
//
// It is a value, not an absence, and it arrives on episodes whose season the
// scanner never worked out. Left alone it names a row that cannot exist, so an
// episode carrying it becomes a child of nothing: 425 episodes here were
// unreachable from their own series page because of it.
const ZeroGUID = "00000000000000000000000000000000"

func NormalizeID(guid string) string {
	if guid == "" {
		return ""
	}
	var b strings.Builder
	b.Grow(32)
	for _, c := range guid {
		switch {
		case c == '-':
			continue
		case c >= 'A' && c <= 'F':
			b.WriteRune(c + ('a' - 'A'))
		case (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'):
			b.WriteRune(c)
		default:
			// Not a GUID at all. Returning it unchanged would put a malformed id
			// in a primary key; empty is the honest answer and the caller skips
			// the row.
			return ""
		}
	}
	if b.Len() != 32 {
		return ""
	}
	// Empty, not the zeros: every caller already handles "no id", and none of
	// them handles "an id that is real-looking and matches nothing".
	if b.String() == ZeroGUID {
		return ""
	}
	return b.String()
}
