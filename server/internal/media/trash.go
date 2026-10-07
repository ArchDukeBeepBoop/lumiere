package media

import (
	"errors"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"strings"
	"time"
)

// Trash moves a file or folder to the Trash, and never unlinks it.
//
// The one place this server touches media on disk, and the Trash is what
// makes that tolerable: a mistake is a drag back out of a folder rather than
// a restore from a backup. macOS keeps a Trash per volume — `.Trashes/<uid>`
// on an external drive, `~/.Trash` on the boot disk — and a move has to stay
// on the volume the file is on or it becomes a copy.
//
// A name collision in the Trash gets a timestamp, the way Finder appends one.
func Trash(path string) (string, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", err
	}
	_ = info
	dest, err := trashDir(path)
	if err != nil {
		return "", err
	}
	target := filepath.Join(dest, filepath.Base(path))
	if _, err := os.Stat(target); err == nil {
		stamp := time.Now().Format("15.04.05")
		ext := filepath.Ext(target)
		target = strings.TrimSuffix(target, ext) + " " + stamp + ext
	}
	if err := os.Rename(path, target); err != nil {
		return "", fmt.Errorf("move to trash: %w", err)
	}
	return target, nil
}

func trashDir(path string) (string, error) {
	u, err := user.Current()
	if err != nil {
		return "", err
	}
	if strings.HasPrefix(path, "/Volumes/") {
		parts := strings.SplitN(strings.TrimPrefix(path, "/Volumes/"), "/", 2)
		if len(parts) == 2 {
			dir := filepath.Join("/Volumes", parts[0], ".Trashes", u.Uid)
			if err := os.MkdirAll(dir, 0o700); err == nil {
				return dir, nil
			}
			// A volume that will not take a Trash folder — a network share,
			// typically — is one where a "delete" cannot be undone. Refuse
			// rather than fall through to a real unlink.
			return "", errors.New("this volume has no Trash; the file was not touched")
		}
	}
	dir := filepath.Join(u.HomeDir, ".Trash")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	return dir, nil
}
