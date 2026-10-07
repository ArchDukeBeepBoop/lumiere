package jellyfin

// MediaSource is the object the client's playback decision is made from (§5.3).
//
// Most of what Jellyfin emits here is decoded and ignored: SupportsDirectPlay,
// SupportsDirectStream, SupportsTranscoding, TranscodingUrl and
// TranscodingSubProtocol are all read by Lumiere and then discarded, because it
// builds its own URLs and makes its own routing decision from Container and the
// stream codecs. The spec says outright that a replacement server need not
// compute any of them. They are emitted anyway, as constants, because a client
// that is not Lumiere may well branch on them and they cost nothing.
type MediaSource struct {
	Id       string `json:"Id"`
	Name     string `json:"Name,omitempty"`
	Path     string `json:"Path,omitempty"`
	Protocol string `json:"Protocol"`
	Type     string `json:"Type"`

	// Container is decisive: lowercased and matched against mp4, m4v, mov, qt
	// to decide whether AVPlayer can take the file directly.
	Container string `json:"Container"`

	Size         *int64 `json:"Size,omitempty"`
	Bitrate      *int   `json:"Bitrate,omitempty"`
	RunTimeTicks *int64 `json:"RunTimeTicks,omitempty"`

	MediaStreams []MediaStream `json:"MediaStreams"`

	DefaultAudioStreamIndex    *int `json:"DefaultAudioStreamIndex,omitempty"`
	DefaultSubtitleStreamIndex *int `json:"DefaultSubtitleStreamIndex,omitempty"`

	SupportsDirectPlay   bool   `json:"SupportsDirectPlay"`
	SupportsDirectStream bool   `json:"SupportsDirectStream"`
	SupportsTranscoding  bool   `json:"SupportsTranscoding"`
	IsRemote             bool   `json:"IsRemote"`
	IsInfiniteStream     bool   `json:"IsInfiniteStream"`
	RequiresOpening      bool   `json:"RequiresOpening"`
	RequiresClosing      bool   `json:"RequiresClosing"`
	RequiresLooping      bool   `json:"RequiresLooping"`
	SupportsProbing      bool   `json:"SupportsProbing"`
	VideoType            string `json:"VideoType,omitempty"`
}

// MediaStream is one track. Index and Type are required; Codec drives the
// entire routing decision on the client side.
type MediaStream struct {
	Index int    `json:"Index"`
	Type  string `json:"Type"`
	Codec string `json:"Codec,omitempty"`

	Language     string `json:"Language,omitempty"`
	Title        string `json:"Title,omitempty"`
	DisplayTitle string `json:"DisplayTitle,omitempty"`

	IsDefault  bool `json:"IsDefault"`
	IsForced   bool `json:"IsForced"`
	IsExternal bool `json:"IsExternal"`

	Width    *int `json:"Width,omitempty"`
	Height   *int `json:"Height,omitempty"`
	BitDepth *int `json:"BitDepth,omitempty"`
	// Profile decodes as an int or a string on the client, so either is safe;
	// this server has it as text.
	Profile string `json:"Profile,omitempty"`

	// Dolby Vision detection reads all four: a non-null DvProfile, or a range
	// string containing DOVI or DOLBY, routes playback to mpv.
	VideoRange     string `json:"VideoRange,omitempty"`
	VideoRangeType string `json:"VideoRangeType,omitempty"`
	DvProfile      *int   `json:"DvProfile,omitempty"`
	DvLevel        *int   `json:"DvLevel,omitempty"`

	AverageFrameRate *float64 `json:"AverageFrameRate,omitempty"`
	RealFrameRate    *float64 `json:"RealFrameRate,omitempty"`
	Channels         *int     `json:"Channels,omitempty"`
	SampleRate       *int     `json:"SampleRate,omitempty"`
	ChannelLayout    string   `json:"ChannelLayout,omitempty"`
	BitRate          *int     `json:"BitRate,omitempty"`

	// Path is the file an external subtitle lives in; the client fetches those
	// over HTTP rather than expecting them in-band.
	Path string `json:"Path,omitempty"`
}

// Chapter is a mark on the scrub bar.
type Chapter struct {
	StartPositionTicks int64  `json:"StartPositionTicks"`
	Name               string `json:"Name,omitempty"`
	ImageTag           string `json:"ImageTag,omitempty"`
}
