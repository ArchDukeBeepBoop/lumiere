package lint

import (
	"bytes"
	"go/format"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestEverythingIsGofmted keeps `gofmt -l` quiet, so a new file that is not
// formatted stands out instead of joining a list nobody reads.
func TestEverythingIsGofmted(t *testing.T) {
	root := "../.."
	filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".go") {
			return err
		}
		src, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		formatted, err := format.Source(src)
		if err != nil {
			t.Errorf("%s does not parse: %v", path, err)
			return nil
		}
		if !bytes.Equal(src, formatted) {
			rel, _ := filepath.Rel(root, path)
			t.Errorf("%s is not gofmt-formatted — run gofmt -w %s", rel, rel)
		}
		return nil
	})
}
