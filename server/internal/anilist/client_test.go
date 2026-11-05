package anilist

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func TestADroppedConnectionIsTriedAgain(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if calls.Add(1) == 1 {
			conn, _, _ := w.(http.Hijacker).Hijack()
			conn.Close()
			return
		}
		w.Write([]byte(`{"data":{"Page":{"media":[{"id":20593,"format":"TV","title":{"romaji":"Hanamonogatari"}}]}}}`))
	}))
	defer srv.Close()
	c := &Client{HTTP: srv.Client(), Endpoint: srv.URL, Pace: time.Millisecond}
	nodes, err := c.Fetch(context.Background(), []int{20593})
	if err != nil || len(nodes) != 1 || nodes[0].Banner != NoBanner {
		t.Fatalf("after one dropped connection: %v %+v", err, nodes)
	}
}
