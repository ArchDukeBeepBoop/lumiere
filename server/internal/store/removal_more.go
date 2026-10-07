package store

import (
	"database/sql"
	"encoding/json"
	"fmt"
)

// Split from removal.go for the 300-line rule.

func insertRowJSON(tx *sql.Tx, row string) error {
	var fields map[string]any
	if err := json.Unmarshal([]byte(row), &fields); err != nil {
		return err
	}
	columns := make([]string, 0, len(fields))
	values := make([]any, 0, len(fields))
	marks := ""
	for column, value := range fields {
		columns = append(columns, column)
		values = append(values, value)
		if marks != "" {
			marks += ","
		}
		marks += "?"
	}
	query := "INSERT OR REPLACE INTO item (" + joinColumns(columns) + ") VALUES (" + marks + ")"
	_, err := tx.Exec(query, values...)
	return err
}

func joinColumns(columns []string) string {
	out := ""
	for i, c := range columns {
		if i > 0 {
			out += ","
		}
		out += fmt.Sprintf("%q", c)
	}
	return out
}
