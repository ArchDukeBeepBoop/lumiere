package store

import "testing"

func resumeFixture(t *testing.T) *Store {
	t.Helper()
	s := testStore(t)
	// Runtime in ticks: 100 ticks stands in for a whole file, so the
	// percentages below read directly.
	if _, err := s.DB.Exec(`
		INSERT INTO item (id, type, name, runtime_ticks, is_folder)
		VALUES ('half',    'Episode', 'Halfway',      100, 0),
		       ('finished','Episode', 'At the end',   100, 0),
		       ('credits', 'Episode', 'In the credits',100, 0),
		       ('played',  'Episode', 'Marked watched',100, 0),
		       ('unknown', 'Episode', 'No runtime',   NULL, 0);
		INSERT INTO user_data (item_id, position_ticks, played, updated_at)
		VALUES ('half',    50,  0, '2026-09-01T00:00:00Z'),
		       ('finished',100, 0, '2026-09-01T00:00:00Z'),
		       ('credits', 95,  0, '2026-09-01T00:00:00Z'),
		       ('played',  50,  1, '2026-09-01T00:00:00Z'),
		       ('unknown', 50,  0, '2026-09-01T00:00:00Z')`); err != nil {
		t.Fatal(err)
	}
	return s
}

func TestResumeDropsWhatIsEffectivelyFinished(t *testing.T) {
	s := resumeFixture(t)

	items, err := s.Resume(true, 20)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]bool{}
	for _, it := range items {
		got[it.ID] = true
	}

	// Halfway through is the case the shelf exists for; an unknown runtime
	// cannot be measured, so it stays rather than vanishing silently.
	for _, id := range []string{"half", "unknown"} {
		if !got[id] {
			t.Errorf("%s should still be on the shelf", id)
		}
	}
	// The last frame, the credits, and an explicitly watched row are all done.
	for _, id := range []string{"finished", "credits", "played"} {
		if got[id] {
			t.Errorf("%s is finished and should not be on the shelf", id)
		}
	}
}

func TestResumeKeepsSomethingJustUnderTheThreshold(t *testing.T) {
	s := resumeFixture(t)
	// 89% is still worth finishing; the cut is at 90 and has to be exclusive of
	// what is below it, or a long film loses its last stretch.
	if _, err := s.DB.Exec(
		`UPDATE user_data SET position_ticks = 89 WHERE item_id = 'credits'`,
	); err != nil {
		t.Fatal(err)
	}
	items, err := s.Resume(true, 20)
	if err != nil {
		t.Fatal(err)
	}
	for _, it := range items {
		if it.ID == "credits" {
			return
		}
	}
	t.Error("89% should still be on the shelf")
}
