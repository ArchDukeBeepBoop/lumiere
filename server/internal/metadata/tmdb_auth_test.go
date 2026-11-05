package metadata

import (
	"context"
	"net/http"
	"strings"
	"testing"
)

func TestBothKindsOfTMDBCredentialAreSentTheirOwnWay(t *testing.T) {
	v3 := NewTMDB("0123456789abcdef0123456789abcdef")
	req, err := v3.request(context.Background(), "/3/search/tv", nil)
	if err != nil {
		t.Fatal(err)
	}
	if req.URL.Query().Get("api_key") != v3.Token || req.Header.Get("Authorization") != "" {
		t.Errorf("a v3 key goes in api_key, never a header: %s %q", req.URL.RawQuery, req.Header.Get("Authorization"))
	}

	v4 := NewTMDB("eyJhbGciOiJIUzI1NiJ9.not-a-real-token.signature")
	req, _ = v4.request(context.Background(), "/3/search/tv", nil)
	if req.URL.Query().Has("api_key") || req.Header.Get("Authorization") != "Bearer "+v4.Token {
		t.Errorf("a v4 token is a Bearer header: %s %q", req.URL.RawQuery, req.Header.Get("Authorization"))
	}
}

func TestAFailedRequestNeverQuotesTheKey(t *testing.T) {
	v3 := NewTMDB("0123456789abcdef0123456789abcdef")
	v3.HTTP = &http.Client{Transport: refuse{}}
	err := v3.get(context.Background(), "/3/search/tv", nil, &struct{}{})
	if err == nil || strings.Contains(err.Error(), v3.Token) {
		t.Errorf("the key leaked into an error: %v", err)
	}
}

type refuse struct{}

func (refuse) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, context.DeadlineExceeded
}
