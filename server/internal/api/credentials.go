package api

import (
	"net/http"
	"strings"
)

// Credentials are what a request claims about itself.
//
// Parsing this is the whole of Batch 2's risk surface. The spec (§3.2) says
// plainly that these header details "have already broken sign-in once and will
// again", so the parser is a pure function with the awkward cases written down
// as tests rather than a few lines inlined in a handler.
type Credentials struct {
	Client   string
	Device   string
	DeviceID string
	Version  string
	Token    string
}

// CredentialsFrom reads whichever of the three credential headers are present.
//
// Three, not one, and all three are real:
//
//   - `Authorization: MediaBrowser Client="…", …` — the standard header.
//   - `X-Emby-Authorization` — the same value, sent alongside it, always. Older
//     Emby clients used only this one and Jellyfin still accepts it.
//   - `X-Emby-Token` — the bare token, and the only thing AVPlayer and mpv can
//     send. mpv's --http-header-fields is itself comma-separated, so the
//     MediaBrowser value arrives split into four broken headers. Refusing this
//     header means nothing plays; see §3.3.
//
// A token found in any of them counts. The MediaBrowser pairs are read from
// whichever of the two scheme headers parses, preferring Authorization.
func CredentialsFrom(h http.Header) Credentials {
	c := parseMediaBrowser(h.Get("Authorization"))
	if c.empty() {
		c = parseMediaBrowser(h.Get("X-Emby-Authorization"))
	}
	if c.Token == "" {
		// Not a fallback so much as a separate, equally valid credential: the
		// media engines send this and nothing else.
		c.Token = strings.TrimSpace(h.Get("X-Emby-Token"))
	}
	return c
}

func (c Credentials) empty() bool {
	return c.Client == "" && c.Device == "" && c.DeviceID == "" &&
		c.Version == "" && c.Token == ""
}

// parseMediaBrowser reads `MediaBrowser Key="Value", Key="Value"`.
//
// Deliberately forgiving about everything except the quoting:
//
//   - The scheme match is case-insensitive, and `Emby` is accepted beside
//     `MediaBrowser` because that is what the header name implies and it costs
//     one comparison.
//   - Unknown keys are ignored rather than rejected. A future client version
//     adding a pair must not turn into a failed sign-in.
//   - Before sign-in the Token pair is absent entirely — not empty — so an
//     absent key can never be distinguished from an empty one here, and must
//     not need to be.
//
// Values are split on commas, which is safe only because Lumiere sanitises its
// own values to printable ASCII minus `"`, `,` and `\` before sending (§3.2). A
// quoted comma would break this, and the client guarantees there isn't one.
func parseMediaBrowser(raw string) Credentials {
	raw = strings.TrimSpace(raw)
	scheme, rest, found := strings.Cut(raw, " ")
	if !found {
		return Credentials{}
	}
	switch strings.ToLower(scheme) {
	case "mediabrowser", "emby":
	default:
		return Credentials{}
	}

	var c Credentials
	for _, pair := range strings.Split(rest, ",") {
		key, value, ok := strings.Cut(strings.TrimSpace(pair), "=")
		if !ok {
			continue
		}
		value = strings.Trim(strings.TrimSpace(value), `"`)
		if value == "" {
			continue
		}
		switch strings.ToLower(strings.TrimSpace(key)) {
		case "client":
			c.Client = value
		case "device":
			c.Device = value
		case "deviceid":
			c.DeviceID = value
		case "version":
			c.Version = value
		case "token", "accesstoken":
			c.Token = value
		}
	}
	return c
}
