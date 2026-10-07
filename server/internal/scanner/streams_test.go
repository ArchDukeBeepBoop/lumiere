package scanner

import "testing"

func TestStreamsFromProbe(t *testing.T) {
	rows, err := ParseStreams([]byte(`{"streams":[
		{"index":0,"codec_type":"video","codec_name":"hevc","profile":"Main 10","width":2160,"height":1080,"pix_fmt":"yuv420p10le","avg_frame_rate":"24000/1001","disposition":{"default":1}},
		{"index":1,"codec_type":"audio","codec_name":"eac3","channels":6,"channel_layout":"5.1(side)","sample_rate":"48000","tags":{"language":"eng"}},
		{"index":2,"codec_type":"subtitle","codec_name":"ass","tags":{"language":"eng","title":"Full"},"disposition":{"forced":0}},
		{"index":3,"codec_type":"attachment","codec_name":"ttf"},
		{"index":4,"codec_type":"video","codec_name":"mjpeg","disposition":{"attached_pic":1}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 3 {
		t.Fatalf("fonts and cover art are not tracks: %d rows", len(rows))
	}
	if rows[0].BitDepth != 10 || rows[0].Width != 2160 || rows[0].FrameRate < 23.9 {
		t.Errorf("video %+v", rows[0])
	}
	if rows[1].Codec != "eac3" || rows[1].Channels != 6 || rows[1].Language != "eng" {
		t.Errorf("audio %+v", rows[1])
	}
	if rows[2].Type != "Subtitle" || rows[2].Title != "Full" {
		t.Errorf("subtitle %+v", rows[2])
	}
}
