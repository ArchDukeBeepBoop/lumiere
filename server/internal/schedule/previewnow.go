package schedule

import (
	"lumiere-server/internal/media"
)

// PreviewFor makes the scrubbing previews of one file, now, because someone
// is watching it. Most of a library waits for the quiet hours — 39,000 of
// 45,000 files here, on a server that is off whenever its drive is out —
// so "the preview stopped working" was the file simply not reached yet.
// One at a time; a second request while one runs is dropped, not queued.
func (k *Keeper) PreviewFor(id string) bool {
	ffmpeg := media.FindFFmpeg()
	if ffmpeg == "" || k.TrickplayRoot == "" {
		return false
	}
	f, ok := k.Store.PreviewTarget(id)
	if !ok {
		return false
	}
	k.mu.Lock()
	if k.working != "" {
		k.mu.Unlock()
		return false
	}
	k.working = f.Path
	k.mu.Unlock()
	go func() {
		defer func() {
			k.mu.Lock()
			k.working = ""
			k.mu.Unlock()
		}()
		info, err := media.MakeTrickplay(ffmpeg, f.Path, f.RuntimeSeconds, media.TrickplayDir(k.TrickplayRoot, f.ID))
		if err != nil {
			k.Log.Info("previews: could not make", "file", f.Path, "error", err)
			k.Store.PreviewFailed(f.ID, media.VideoFingerprint(f.Path))
			return
		}
		k.Store.SetItemValue(f.ID, "trickplay", media.EncodeTrickplay(info))
		k.Log.Info("previews made on request", "item", f.ID)
	}()
	return true
}
