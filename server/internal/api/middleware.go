package api

import (
	"context"
	"errors"
	"net/http"

	"lumiere-server/internal/store"
)

// Everything past sign-in needs a token, and there is no session cookie, no
// refresh and no expiry anywhere in the client: a token is valid until this
// server rejects it (§3.3). So validation is a single lookup, and the only way
// out is a 401 — which Lumiere surfaces as signed-out.

type sessionKey struct{}

// SessionFrom returns the session a request authenticated with.
func SessionFrom(ctx context.Context) (store.Session, bool) {
	s, ok := ctx.Value(sessionKey{}).(store.Session)
	return s, ok
}

// Auth validates credentials on the way in.
type Auth struct {
	Store *store.Store
}

// RequireAuth rejects anything without a valid token.
//
// The token may arrive in `Authorization`, `X-Emby-Authorization` or
// `X-Emby-Token`, and all three are accepted on every route rather than only on
// the streaming ones. Restricting the bare-token header to media URLs would mean
// deciding, per route, which of them AVPlayer and mpv might touch — a list that
// is wrong the first time a subtitle or trickplay URL is added.
func (a Auth) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := CredentialsFrom(r.Header).Token
		if token == "" {
			unauthorized(w)
			return
		}
		sess, err := a.Store.LookupToken(token)
		if err != nil {
			if !errors.Is(err, store.ErrNoAccount) {
				// A database failure is not a bad token, but the client can only
				// act on one of those. 500 keeps it from discarding a good token
				// because the disk was busy.
				writeJSON(w, http.StatusInternalServerError, errorBody{"auth lookup failed"})
				return
			}
			unauthorized(w)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), sessionKey{}, sess)))
	})
}
