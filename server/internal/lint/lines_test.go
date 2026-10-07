// Package lint holds repository rules that are cheaper to enforce as tests
// than to remember.
package lint

import (
	"bufio"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// TestLineBudget is the 300-line rule, as a ratchet.
//
// Files that had outgrown the rule before this check existed are listed in
// line-budget.txt at the size they were: they may shrink, never grow. Every
// other file fails above 300, so a split happens while it is still easy.
func TestLineBudget(t *testing.T) {
	budget := map[string]int{}
	f, err := os.Open("line-budget.txt")
	if err != nil {
		t.Fatal(err)
	}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) == 2 {
			n, _ := strconv.Atoi(fields[1])
			budget[fields[0]] = n
		}
	}
	f.Close()

	root := "../.."
	filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".go") {
			return err
		}
		rel, _ := filepath.Rel(root, path)
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		lines := strings.Count(string(data), "\n")
		limit, listed := budget[rel]
		if !listed {
			limit = 300
		}
		if lines > limit {
			t.Errorf("%s is %d lines (limit %d) — split it", rel, lines, limit)
		}
		return nil
	})
}
