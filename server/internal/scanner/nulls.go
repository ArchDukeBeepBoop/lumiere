package scanner

func nullString(value string) any {
	if value == "" {
		return nil
	}
	return value
}

func nullInt(value int64) any {
	if value == 0 {
		return nil
	}
	return value
}

func nullInt64(value int64) any { return nullInt(value) }
