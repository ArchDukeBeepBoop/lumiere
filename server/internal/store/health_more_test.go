package store

import "testing"

func TestExtrasNoTitleClaimsAreListed(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, path) VALUES ('show', 'Series', 'S', 1, '/tv/S')`)
	s.DB.Exec(`INSERT INTO item (id, type, name, is_folder, path, extra_type) VALUES
		('in', 'Video', 'Opening', 0, '/tv/S/Extras/Opening.mkv', 'Clip'),
		('out', 'Video', 'Lost', 0, '/tv/Extras/Lost.mkv', 'Clip')`)
	issue, err := s.unplacedExtras()
	if err != nil || issue.Count != 1 || issue.Samples[0].ID != "out" {
		t.Fatalf("got %+v (%v)", issue, err)
	}
}

func TestAFallInCollectionMembersIsRaised(t *testing.T) {
	if DriftWarning(driftCounts{CollectionMembers: 455}, driftCounts{CollectionMembers: 300}) == "" {
		t.Error("a third of collection members gone should warn")
	}
	if DriftWarning(driftCounts{CollectionMembers: 455}, driftCounts{CollectionMembers: 450}) != "" {
		t.Error("a merge taking five should not")
	}
}

func TestHealthSaysWhatChangedSinceTheSnapshot(t *testing.T) {
	s := testStore(t)
	issues := []HealthIssue{{Kind: "DuplicateFilms", Count: 2}}
	s.AttachSince(issues) // the first: takes the snapshot
	if issues[0].Since != nil {
		t.Fatal("no comparison before a snapshot exists")
	}
	later := []HealthIssue{{Kind: "DuplicateFilms", Count: 5}}
	s.AttachSince(later)
	if later[0].Since == nil || *later[0].Since != 2 {
		t.Fatalf("since = %v, want 2", later[0].Since)
	}
}

func TestAShowWhoseFilesDisagreeIsFlagged(t *testing.T) {
	s := testStore(t)
	s.DB.Exec(`INSERT INTO item (id, type, name, path, is_folder) VALUES ('dm', 'Series', 'Dark Matter', '/tv/Dark', 1)`)
	titles := []string{"Secrets", "Lies", "Past and Present", "Double Lives", "Truths"}
	for i, title := range titles {
		// The files are Dark's; the names are another show's.
		s.DB.Exec(`INSERT INTO item (id, type, name, series_id, series_name, path, is_folder)
			VALUES (?, 'Episode', ?, 'dm', 'Dark Matter', ?, 0)`,
			string(rune('a'+i)), "Episode Title "+string(rune('A'+i)),
			"/tv/Dark/Season 1/Dark - 1x0"+string(rune('1'+i))+" - "+title+".mkv")
	}
	issue, err := s.mismatchedShows()
	if err != nil || issue.Count != 1 || issue.Samples[0].Name != "Dark Matter" {
		t.Fatalf("got %+v (%v)", issue, err)
	}
	if !titlesAgree("Pilot", "Pilot (Part 1)") || titlesAgree("Secrets", "Being Human") {
		t.Error("titlesAgree")
	}
}

func TestGapLabelsSeparateHolesFromNewEpisodes(t *testing.T) {
	if got := GapLabel(2, []int{5, 7, 8, 9}, []int{11, 12}); got != "season 2: 5, 7–9 missing; 11, 12 aired since" {
		t.Errorf("got %q", got)
	}
	if got := Ranges([]int{3, 1, 2, 9}); got != "1–3, 9" {
		t.Errorf("got %q", got)
	}
}
