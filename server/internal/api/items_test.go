package api

import (
	"net/url"
	"reflect"
	"testing"
)

func TestQueryFrom(t *testing.T) {
	t.Run("the sync's own parameters", func(t *testing.T) {
		// Copied from the capture: the exact shape of all 411 /Items calls.
		v, _ := url.ParseQuery("userId=13fd&Recursive=true&SortBy=SortName" +
			"&SortOrder=Ascending&StartIndex=400&Limit=50&EnableTotalRecordCount=true" +
			"&EnableImageTypes=Primary,Backdrop,Thumb,Logo" +
			"&ParentId=0c419071-0000-0000-0000-000000000000" +
			"&Fields=Path,DateCreated,ExtraType,ParentId,Overview,OriginalTitle,Genres")
		q := queryFrom(v)
		if q.ParentID != "0c419071000000000000000000000000" {
			t.Errorf("ParentId not normalised: %q", q.ParentID)
		}
		if !q.Recursive || q.StartIndex != 400 || q.Limit != 50 || q.Descending {
			t.Errorf("%+v", q)
		}
		if !reflect.DeepEqual(q.SortBy, []string{"SortName"}) {
			t.Errorf("SortBy %v", q.SortBy)
		}
	})

	t.Run("Genres is pipe-separated, everything else is commas", func(t *testing.T) {
		// Jellyfin's own inconsistency, and it has to be matched: genre names
		// contain commas, so splitting them on one loses half of every such name.
		v, _ := url.ParseQuery("Genres=Action%2C%20Adventure%7CComedy&IncludeItemTypes=Series,Season")
		q := queryFrom(v)
		if !reflect.DeepEqual(q.Genres, []string{"Action, Adventure", "Comedy"}) {
			t.Errorf("Genres %q", q.Genres)
		}
		if !reflect.DeepEqual(q.Types, []string{"Series", "Season"}) {
			t.Errorf("Types %q", q.Types)
		}
	})

	t.Run("parameter names are matched without regard to case", func(t *testing.T) {
		// Lumiere sends `userId` and `SortBy` in the same URL; a server that
		// matched exactly would honour one and drop the other.
		// The id must be a real one: NormalizeID shape-checks, so a value that
		// is not 32 hex characters is dropped rather than passed to the SQL.
		v, _ := url.ParseQuery("parentid=0C419071-0000-0000-0000-000000000000" +
			"&RECURSIVE=true&sortorder=descending")
		q := queryFrom(v)
		if q.ParentID == "" || !q.Recursive || !q.Descending {
			t.Errorf("%+v", q)
		}
	})

	t.Run("junk numbers fall back rather than failing", func(t *testing.T) {
		v, _ := url.ParseQuery("StartIndex=nonsense&Limit=&Years=1999,notayear,2001")
		q := queryFrom(v)
		if q.StartIndex != 0 || q.Limit != 0 {
			t.Errorf("%+v", q)
		}
		if !reflect.DeepEqual(q.Years, []int{1999, 2001}) {
			t.Errorf("Years %v", q.Years)
		}
	})
}
