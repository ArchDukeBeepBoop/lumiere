package store

import "testing"

func TestTitleFromFilename(t *testing.T) {
	for name, want := range map[string]string{
		"Justice League - 3x03 - Kid Stuff":                               "Kid Stuff",
		"Avatar - The Last Airbender - S02E17 - Lake Laogai":              "Lake Laogai",
		"3x3 Eyes - 1x01 - Transmigration":                                "Transmigration",
		"Welcome to Demon School! Iruma-kun - 1x02 - Familiars Summoned!": "Familiars Summoned!",
	} {
		got, ok := TitleFromFilename(name)
		if !ok || got != want {
			t.Errorf("%q → %q, %v; want %q", name, got, ok, want)
		}
	}
	for _, name := range []string{"Show - 1x04", "Show S01E04", "Show - 1x04 - 1080"} {
		if got, ok := TitleFromFilename(name); ok {
			t.Errorf("%q gave a title %q, want none", name, got)
		}
	}
}

func TestOnlyEpisodesTMDBAnsweredForTakeTheirFileTitle(t *testing.T) {
	s := testStore(t)
	for _, q := range []string{
		`INSERT INTO item (id, type, name, is_folder) VALUES ('asked', 'Episode', 'Justice League - 3x03 - Kid Stuff', 0)`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('asked', 'provider:none', '')`,
		`INSERT INTO item (id, type, name, is_folder) VALUES ('fresh', 'Episode', 'Justice League - 3x04 - Dark Heart', 0)`,
		`INSERT INTO item (id, type, name, is_folder) VALUES ('locked', 'Episode', 'Justice League - 3x05 - Ultimatum', 0)`,
		`INSERT INTO item_value (item_id, kind, value) VALUES ('locked', 'provider:none', ''), ('locked', 'lock:name', '1')`,
	} {
		if _, err := s.DB.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	n, err := s.TitleUnmatchedEpisodes()
	if err != nil || n != 1 {
		t.Fatalf("renamed %d (%v), want 1", n, err)
	}
	names := map[string]string{}
	rows, _ := s.DB.Query(`SELECT id, name FROM item`)
	for rows.Next() {
		var id, name string
		rows.Scan(&id, &name)
		names[id] = name
	}
	rows.Close()
	if names["asked"] != "Kid Stuff" {
		t.Errorf("asked = %q, want the file's title", names["asked"])
	}
	if names["fresh"] != "Justice League - 3x04 - Dark Heart" {
		t.Error("an episode TMDB has not been asked about was renamed first")
	}
	if names["locked"] != "Justice League - 3x05 - Ultimatum" {
		t.Error("a locked name was changed")
	}
}
