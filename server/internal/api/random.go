package api

import (
	"crypto/rand"
	"encoding/hex"
)

// randomHex32 returns 32 lowercase hex characters — the shape of every id in
// this API.
func randomHex32() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(b[:]), nil
}
