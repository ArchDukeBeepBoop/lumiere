package metadata

import "testing"

func TestFitCountsSeasonsWhoseSizesMatch(t *testing.T) {
	local := map[int]int{0: 3, 1: 26, 2: 25, 3: 13}
	if f := Fit(local, map[int]int{1: 26, 2: 25, 3: 13}); f != 1 {
		t.Errorf("a perfect order fits %.2f", f)
	}
	if f := Fit(local, map[int]int{1: 52, 2: 12}); f != 0 {
		t.Errorf("a different split fits %.2f", f)
	}
	if f := Fit(local, map[int]int{1: 26, 2: 12, 3: 13}); f < 0.66 || f > 0.67 {
		t.Errorf("two of three fits %.2f", f)
	}
}
