package api

import (
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha512"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"strconv"
	"strings"
)

// Jellyfin's stored password format, verified against the live database:
//
//	$PBKDF2-SHA512$iterations=210000$<salt hex>$<hash hex>
//
// Re-implemented here rather than imported because it is twenty lines and the
// alternative is a dependency on Jellyfin's server assemblies. The parameters
// are read from the string, never assumed: an older row written with a different
// iteration count must still verify, and hardcoding 210000 would lock this
// server to whatever the instance happened to use on the day it was read.
var errBadHashFormat = errors.New("unrecognised password hash format")

type pbkdf2Hash struct {
	iterations int
	salt       []byte
	want       []byte
}

func parseJellyfinHash(stored string) (pbkdf2Hash, error) {
	parts := strings.Split(stored, "$")
	// Leading "$" makes the first field empty: ["", "PBKDF2-SHA512", "iterations=N", salt, hash]
	if len(parts) != 5 || parts[0] != "" {
		return pbkdf2Hash{}, errBadHashFormat
	}
	if !strings.EqualFold(parts[1], "PBKDF2-SHA512") {
		// SHA-256 and the older unsalted schemes exist in Jellyfin's history.
		// Failing loudly beats verifying with the wrong function and rejecting a
		// correct password as if it were wrong.
		return pbkdf2Hash{}, errBadHashFormat
	}
	iters, err := strconv.Atoi(strings.TrimPrefix(parts[2], "iterations="))
	if err != nil || iters <= 0 {
		return pbkdf2Hash{}, errBadHashFormat
	}
	salt, err := hex.DecodeString(parts[3])
	if err != nil {
		return pbkdf2Hash{}, errBadHashFormat
	}
	want, err := hex.DecodeString(parts[4])
	if err != nil {
		return pbkdf2Hash{}, errBadHashFormat
	}
	return pbkdf2Hash{iterations: iters, salt: salt, want: want}, nil
}

// verifyPassword reports whether pw matches the stored hash.
//
// An account with no stored hash is a real Jellyfin state — a user with no
// password — and it returns false here rather than true. "No password set"
// silently becoming "every password works" is the failure mode worth spending a
// line to rule out; if passwordless sign-in is ever wanted it should be an
// explicit decision, not the default behaviour of a missing column.
func verifyPassword(stored, pw string) bool {
	if stored == "" {
		return false
	}
	h, err := parseJellyfinHash(stored)
	if err != nil {
		return false
	}
	got, err := pbkdf2.Key(sha512.New, pw, h.salt, h.iterations, len(h.want))
	if err != nil {
		return false
	}
	// Constant-time, because the comparison is the one place a wrong answer
	// leaks how nearly right it was.
	return subtle.ConstantTimeCompare(got, h.want) == 1
}

// hashPassword writes a new password in the same format verifyPassword reads.
func hashPassword(pw string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	const iterations = 210000
	key, err := pbkdf2.Key(sha512.New, pw, salt, iterations, 64)
	if err != nil {
		return "", err
	}
	return "$PBKDF2-SHA512$iterations=" + strconv.Itoa(iterations) + "$" +
		strings.ToUpper(hex.EncodeToString(salt)) + "$" + strings.ToUpper(hex.EncodeToString(key)), nil
}
