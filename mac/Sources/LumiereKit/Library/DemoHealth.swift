import Foundation

public extension LibraryHealthIssue {
    /// Library Health for the demo library: one of each finding with a fix,
    /// so the walkthrough has every row and button to show.
    static var demo: [LibraryHealthIssue] {
        let json = #"""
        [
         {"Kind": "DuplicateCollections", "Count": 1, "Since": 0, "Samples": [
           {"ID": "col-dup", "Name": "Starlight Collection", "Path": "",
            "Parts": [{"ID": "col-1", "Name": "Starlight"}]}]},
         {"Kind": "DuplicateFilms", "Count": 1, "Samples": [
           {"ID": "movie-3", "Name": "The Long Quiet (2019)", "Path": "/Demo/Films/The Long Quiet",
            "Parts": [{"ID": "movie-3", "Name": "2160p HEVC HDR10 · 18.2 GB · 3 audio · 12 subtitles — The Long Quiet (2019).mkv"},
                      {"ID": "movie-3b", "Name": "1080p H.264 · 4.1 GB · 1 audio · 2 subtitles — The Long Quiet (2019) 1080p.mp4"}]}]},
         {"Kind": "MismatchedShows", "Count": 1, "Samples": [{"ID": "series-2", "Name": "Harbour Lights", "Path": ""}]},
         {"Kind": "EmptyCollections", "Count": 1, "Samples": [{"ID": "col-empty", "Name": "Northern Trilogy", "Path": ""}]},
         {"Kind": "UnnamedEpisodes", "Count": 3, "Since": 1, "Samples": [
           {"ID": "ep-x", "Name": "Harbour Lights - 1x04 - The Tide Turns", "Path": ""}]},
         {"Kind": "MissingEpisodes", "Count": 4, "Samples": [
           {"ID": "series-1", "Name": "Marble Hall — 4 missing: season 2: 5, 7–9 missing", "Path": "",
            "Parts": [{"ID": "s2", "Name": "season 2: 5, 7–9 missing"}]}]}
        ]
        """#
        return (try? JSONDecoder().decode([LibraryHealthIssue].self, from: Data(json.utf8))) ?? []
    }
}
