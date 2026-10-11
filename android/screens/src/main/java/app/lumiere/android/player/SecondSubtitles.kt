package app.lumiere.android.player

/**
 * A second language under the first, as you'd want learning one or
 * watching with someone who reads another: a film's other text subtitles,
 * fetched from the server as WebVTT and read here, shown by the Theater's
 * captions beneath the player's own. Pure, so it's tested without a player.
 */
object SecondSubtitles {
    data class Cue(val startMs: Long, val endMs: Long, val text: String)

    /** The track chosen: its stream's index, what it's called, and its lines. */
    data class Track(val index: Int, val label: String, val cues: List<Cue>)

    /** Image subtitles (Blu-ray, DVD) have no text to read. */
    private val PICTURES = setOf("pgssub", "pgs", "hdmv_pgs_subtitle", "dvdsub", "dvd_subtitle", "dvbsub", "dvb_subtitle", "vobsub")

    /** Whether a subtitle stream of [codec] can be shown as a second language. */
    fun readable(codec: String?): Boolean = codec?.lowercase() !in PICTURES

    /** WebVTT or SubRip text as cues in time order; styling, positions and notes left out. */
    fun parse(text: String): List<Cue> {
        val blocks = text.replace("\r\n", "\n").replace('\r', '\n').split(Regex("\n\\s*\n"))
        val cues = mutableListOf<Cue>()
        for (block in blocks) {
            val lines = block.trim('\n').split('\n')
            val at = lines.indexOfFirst { "-->" in it }
            if (at < 0) continue
            val (from, to) = lines[at].split("-->").let { it[0].trim() to it.getOrElse(1) { "" }.trim().substringBefore(' ') }
            val start = time(from) ?: continue
            val end = time(to) ?: continue
            val body = lines.drop(at + 1).joinToString("\n") { clean(it) }.trim()
            if (body.isNotEmpty() && end > start) cues += Cue(start, end, body)
        }
        return cues.sortedBy { it.startMs }
    }

    /** What's showing at [ms]: every cue on then, one under another. */
    fun at(cues: List<Cue>, ms: Long): String? {
        if (cues.isEmpty()) return null
        // The last cue starting at or before ms, then any overlapping ones before it.
        var lo = 0; var hi = cues.size - 1; var last = -1
        while (lo <= hi) { val mid = (lo + hi) / 2; if (cues[mid].startMs <= ms) { last = mid; lo = mid + 1 } else hi = mid - 1 }
        if (last < 0) return null
        val on = mutableListOf<String>()
        var i = last
        while (i >= 0 && i > last - 8) { val c = cues[i]; if (ms < c.endMs) on.add(0, c.text); i-- }
        return on.takeIf { it.isNotEmpty() }?.joinToString("\n")
    }

    /** "01:02:03.456", "02:03.456" or SubRip's "01:02:03,456", in milliseconds. */
    fun time(s: String): Long? {
        val parts = s.trim().replace(',', '.').split(':')
        if (parts.size !in 2..3) return null
        val secs = parts.last().toDoubleOrNull() ?: return null
        val mins = parts[parts.size - 2].toLongOrNull() ?: return null
        val hours = if (parts.size == 3) parts[0].toLongOrNull() ?: return null else 0L
        return ((hours * 3600 + mins * 60) * 1000 + Math.round(secs * 1000))
    }

    private fun clean(line: String) = line.replace(Regex("<[^>]*>"), "").replace(Regex("\\{\\\\[^}]*\\}"), "")
        .replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&nbsp;", " ").replace("&quot;", "\"")

    /** A stream's name for a person: its language, and its title if it has one. */
    fun label(language: String?, title: String?): String {
        val lang = language?.takeIf { it.isNotBlank() && it != "und" }
            ?.let { runCatching { java.util.Locale.forLanguageTag(it).getDisplayLanguage(java.util.Locale.ENGLISH) }.getOrNull()?.takeIf { n -> n.isNotBlank() && n != it } ?: it }
        return listOfNotNull(lang, title?.takeIf { it.isNotBlank() && it != lang }).joinToString(" · ").ifEmpty { "Unnamed" }
    }
}
