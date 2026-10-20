package scanner

import "testing"

// Filenames are whatever is on the disk. Whatever they are, reading one as a
// title, a season or an episode returns rather than panics.
func FuzzFilenames(f *testing.F) {
	for _, seed := range []string{
		"/m/Show/Season 1/Show - S01E02 - Name.mkv", "/m/Film (2019)/Film (2019).mkv",
		"/m/a/[Group] Show - 03 [1080p].mkv", "/m/S00E00.mkv", "/m/..mkv", "",
	} {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, path string) {
		_ = Describe("/m", path)
		_, _ = CleanTitle(path)
	})
}
