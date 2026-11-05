package metadata

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strings"
)

// request builds a GET carrying whichever of TMDB's two credentials this is.
//
// TMDB's settings page shows both, side by side: the v3 "API Key", 32 hex
// characters, which goes in an api_key parameter, and the v4 "API Read Access
// Token", a long JWT, which goes in a Bearer header. They are not
// interchangeable, and this used to accept only the token — so the key, the
// shorter and more obvious thing to copy, failed every lookup with a 401 that
// read as a bad key rather than the wrong kind. Both work now. Errors name the
// path only, never the URL, so the key in a v3 query never reaches a log.
func (t *TMDB) request(ctx context.Context, path string, query url.Values) (*http.Request, error) {
	if isV3Key(t.Token) {
		if query == nil {
			query = url.Values{}
		}
		query.Set("api_key", t.Token)
	}
	endpoint := url.URL{Scheme: "https", Host: tmdbHost, Path: path}
	if query != nil {
		endpoint.RawQuery = query.Encode()
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return nil, err
	}
	if !isV3Key(t.Token) {
		request.Header.Set("Authorization", "Bearer "+t.Token)
	}
	request.Header.Set("Accept", "application/json")
	return request, nil
}

// ErrKeyRejected is TMDB answering 401: the key is wrong, revoked, or the
// other kind. Every lookup after it would fail the same way.
var ErrKeyRejected = errors.New("TMDB refused the key")

// isV3Key reports a v3 API key: exactly 32 hex characters.
func isV3Key(token string) bool {
	if len(token) != 32 {
		return false
	}
	for _, c := range token {
		if !strings.ContainsRune("0123456789abcdefABCDEF", c) {
			return false
		}
	}
	return true
}
