package metadata

import "context"

// Keywords are the movie database's subject tags for a film or show —
// "time loop", "immortality" — which theme collections are built from.
func (t *TMDB) Keywords(ctx context.Context, series bool, id string) ([]string, error) {
	var body struct {
		Keywords []struct{ Name string } `json:"keywords"`
		Results  []struct{ Name string } `json:"results"`
	}
	path := "/3/movie/" + id + "/keywords"
	if series {
		path = "/3/tv/" + id + "/keywords"
	}
	if err := t.get(ctx, path, nil, &body); err != nil {
		return nil, err
	}
	var out []string
	for _, k := range append(body.Keywords, body.Results...) {
		out = append(out, k.Name)
	}
	return out, nil
}
