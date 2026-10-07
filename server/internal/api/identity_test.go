package api

import "testing"

func TestResolveIdentityKeepsItsIDBetweenStarts(t *testing.T) {
	// An id that changed between restarts would make every app treat each
	// launch as a new server and resync from scratch.
	dir := t.TempDir()
	first, err := ResolveIdentity(dir, "127.0.0.1:8098")
	if err != nil {
		t.Fatal(err)
	}
	if len(first.ServerID) != 32 {
		t.Fatalf("id %q is not 32 hex characters", first.ServerID)
	}
	second, err := ResolveIdentity(dir, "127.0.0.1:8098")
	if err != nil {
		t.Fatal(err)
	}
	if first.ServerID != second.ServerID {
		t.Fatalf("id changed between starts: %q then %q", first.ServerID, second.ServerID)
	}
}
