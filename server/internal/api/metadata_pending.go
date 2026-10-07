package api

import "lumiere-server/internal/metadata"

// pendingCount must ask exactly what PendingItems asks.
//
// It did not: the count kept the narrow "no text *and* no artwork" rule after
// the work widened to "either", so the card said 26 waiting and the pass then
// processed 200. A number on screen that the button disagrees with is worse
// than no number.
func (h *MetadataHandler) pendingCount() (int, error) {
	var count int
	err := h.Store.DB.QueryRow(
		`SELECT count(*) FROM item WHERE ` + metadata.PendingClause,
	).Scan(&count)
	if err != nil {
		return 0, err
	}

	// Seasons with no poster of their own count too: they are work the button
	// will do, and a card reporting nothing to do while a hundred seasons still
	// borrow their show's image is a card nobody would press.
	var seasons int
	if err := h.Store.DB.QueryRow(
		`SELECT count(*) FROM item s
		 JOIN item parent ON parent.id = s.parent_id AND parent.type = 'Series'
		 JOIN item_value v ON v.item_id = parent.id AND v.kind = 'provider:Tmdb'
		 WHERE s.type = 'Season' AND s.index_number IS NOT NULL
		   AND NOT EXISTS (
			 SELECT 1 FROM image g WHERE g.item_id = s.id AND g.kind = 'Primary'
		   )
		   AND NOT EXISTS (
			 SELECT 1 FROM item_value asked
			 WHERE asked.item_id = s.id AND asked.kind = 'provider:none'
		   )`,
	).Scan(&seasons); err != nil {
		return count, nil
	}
	return count + seasons, nil
}
