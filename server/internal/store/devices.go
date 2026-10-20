package store

import "time"

// SignedInDevice is one sign-in, for Settings' device list. The id is a
// prefix of the stored hash: enough to name it, useless as a credential.
type SignedInDevice struct {
	ID       string `json:"Id"`
	Device   string `json:"Device"`
	Client   string `json:"Client"`
	LastSeen string `json:"LastSeen"`
	Current  bool   `json:"Current"`
}

// SignedInDevices lists an account's sign-ins, newest use first.
func (s *Store) SignedInDevices(accountID, currentToken string) ([]SignedInDevice, error) {
	rows, err := s.DB.Query(`SELECT token, COALESCE(device, ''), COALESCE(client, ''), COALESCE(last_seen, '')
		FROM token WHERE account_id = ? ORDER BY last_seen DESC`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	current := HashToken(currentToken)
	out := []SignedInDevice{}
	for rows.Next() {
		var hash string
		var d SignedInDevice
		if err := rows.Scan(&hash, &d.Device, &d.Client, &d.LastSeen); err != nil {
			return nil, err
		}
		d.ID = hash[:16]
		d.Current = hash == current
		if t, err := time.Parse(time.RFC3339, d.LastSeen); err == nil {
			d.LastSeen = t.UTC().Format(time.RFC3339)
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// SignOutDevice ends one of an account's sign-ins by its id.
func (s *Store) SignOutDevice(accountID, id string) (bool, error) {
	if len(id) != 16 {
		return false, nil
	}
	res, err := s.DB.Exec(`DELETE FROM token WHERE account_id = ? AND substr(token, 1, 16) = ?`, accountID, id)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}
