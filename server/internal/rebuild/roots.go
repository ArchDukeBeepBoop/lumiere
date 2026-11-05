package rebuild

import (
	"database/sql"
	"path/filepath"
	"sort"
	"strings"
)

// minDepth keeps a root from being the disk itself: "/Volumes/Drive" splits
// into three parts, and nothing shallower than that is a library folder.
const minDepth = 3

// Roots works out each library's folders on disk from where its items live.
//
// The cache never held the folders, only the items, so a library's root is the
// shallowest folder that holds its items and nobody else's. Shallowest, so a
// library is one folder rather than a thousand series folders; nobody else's,
// because three libraries here share one parent folder and a root at that
// parent would pull each of them into the others.
//
// dirs maps a folder to the library whose item lives in it. Pure.
func Roots(dirs map[string]string) map[string][]string {
	owners := map[string]map[string]bool{}
	for dir, lib := range dirs {
		for _, prefix := range prefixes(dir) {
			if owners[prefix] == nil {
				owners[prefix] = map[string]bool{}
			}
			owners[prefix][lib] = true
		}
	}

	chosen := map[string]map[string]bool{}
	for dir, lib := range dirs {
		root := dir
		for _, prefix := range prefixes(dir) {
			if len(owners[prefix]) == 1 {
				root = prefix
				break
			}
		}
		if chosen[lib] == nil {
			chosen[lib] = map[string]bool{}
		}
		chosen[lib][root] = true
	}

	out := map[string][]string{}
	for lib, set := range chosen {
		var roots []string
		for root := range set {
			roots = append(roots, root)
		}
		sort.Strings(roots)
		// A root inside another of the same library's roots is already covered.
		// Checked against every kept root, not the last: "/a/b-x" sorts
		// between "/a/b" and "/a/b/c".
		var kept []string
	next:
		for _, r := range roots {
			for _, k := range kept {
				if within(r, k) {
					continue next
				}
			}
			kept = append(kept, r)
		}
		out[lib] = kept
	}
	return out
}

// prefixes are a folder and its parents, shallowest first, from minDepth down.
func prefixes(dir string) []string {
	dir = filepath.Clean(dir)
	parts := strings.Split(dir, "/")
	var out []string
	for k := minDepth; k <= len(parts); k++ {
		out = append(out, strings.Join(parts[:k], "/"))
	}
	return out
}

// The folder a path belongs under: a file's own folder, or a folder row's path.
func dirOf(it cached) string {
	if it.isFolder {
		return filepath.Clean(it.path.String)
	}
	return filepath.Dir(it.path.String)
}

// folderFor is the folder row an item hangs from. An item with no path — a
// show the app synced without one — goes under the library's first folder.
func folderFor(folders map[string]string, path string) string {
	if path == "" {
		first := ""
		for root := range folders {
			if first == "" || root < first {
				first = root
			}
		}
		return folders[first]
	}
	best, id := "", ""
	for root, fid := range folders {
		if within(path, root) && len(root) > len(best) {
			best, id = root, fid
		}
	}
	return id
}

func isRoot(roots []string, path string) bool {
	for _, r := range roots {
		if filepath.Clean(path) == r {
			return true
		}
	}
	return false
}

func within(path, root string) bool {
	return path == root || strings.HasPrefix(path, root+"/")
}

func pipes(s sql.NullString) any {
	if !s.Valid || s.String == "" {
		return nil
	}
	return strings.ReplaceAll(s.String, "\n", "|")
}
