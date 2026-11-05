package metadata

import (
	"reflect"
	"testing"
)

func TestCountriesPreferOriginThenProduction(t *testing.T) {
	type pc = struct {
		Code string `json:"iso_3166_1"`
	}
	if got := countriesOf([]string{"jp", "JP"}, []pc{{"US"}}); !reflect.DeepEqual(got, []string{"JP"}) {
		t.Fatalf("origin wins, deduplicated: %v", got)
	}
	if got := countriesOf(nil, []pc{{"KR"}, {"US"}}); !reflect.DeepEqual(got, []string{"KR", "US"}) {
		t.Fatalf("production when no origin: %v", got)
	}
	if got := countriesOf([]string{"", "XYZ"}, nil); len(got) != 0 {
		t.Fatalf("junk dropped: %v", got)
	}
}
