package app.lumiere.android.api

import org.json.JSONArray
import org.json.JSONObject

/** Ticks are Jellyfin's unit: 10,000,000 to the second. */
const val TICKS_PER_SECOND = 10_000_000L

/** One item from the server, holding only what the screens draw. */
data class Item(
    val id: String,
    val name: String,
    val type: String,
    val overview: String? = null,
    val year: Int? = null,
    val seriesId: String? = null,
    val seriesName: String? = null,
    val seasonId: String? = null,
    val seasonName: String? = null,
    val indexNumber: Int? = null,
    val parentIndexNumber: Int? = null,
    val runtimeTicks: Long? = null,
    val positionTicks: Long = 0,
    val played: Boolean = false,
    val unplayedCount: Int? = null,
    val primaryTag: String? = null,
    val backdropTag: String? = null,
    val parentBackdropId: String? = null,
    val parentBackdropTag: String? = null,
    val seriesPrimaryTag: String? = null,
    val thumbTag: String? = null,
    val officialRating: String? = null,
    val communityRating: Double? = null,
    val genres: List<String> = emptyList(),
    val collectionType: String? = null,
    val isFolder: Boolean = false,
    val mediaSourceId: String? = null,
    val streams: List<MediaStream> = emptyList(),
    val chapters: List<Chapter> = emptyList(),
    /** The library it is in, as UserViews names it. See Privacy. */
    val libraryId: String? = null,
    val album: String? = null,
    val albumId: String? = null,
    val albumArtist: String? = null,
    val artists: List<String> = emptyList(),
    val favorite: Boolean = false,
    val parentId: String? = null,
    val logoTag: String? = null,
    val people: List<Person> = emptyList(),
    val studios: List<String> = emptyList(),
    val extraType: String? = null,
    val childCount: Int? = null,
    /** When it was added to the library, as the server's ISO date — sorts as text. */
    val dateCreated: String? = null,
    /** The file's path on the server, where it says (a VR film's tags are often only in its file name). */
    val path: String? = null,
) {
    val isAudio get() = type == "Audio"
    val isAlbum get() = type == "MusicAlbum"
    val isEpisode get() = type == "Episode"
    val isSeries get() = type == "Series"
    val isPlayable get() = type in setOf("Movie", "Episode", "Video", "MusicVideo", "Trailer")

    /** Fraction watched, for the bar under a card; null when not started. */
    val progress: Float?
        get() {
            val total = runtimeTicks ?: return null
            if (positionTicks <= 0 || total <= 0) return null
            return (positionTicks.toFloat() / total).coerceIn(0f, 1f)
        }

    /** "S1 · E4" for an episode, nothing otherwise. */
    val episodeLabel: String?
        get() {
            if (!isEpisode) return null
            val season = parentIndexNumber?.let { "S$it" }
            val episode = indexNumber?.let { "E$it" }
            return listOfNotNull(season, episode).joinToString(" · ").ifEmpty { null }
        }
}

/** Someone in the cast or crew; [role] is the character for an actor. */
data class Person(val id: String, val name: String, val role: String?, val type: String?, val imageTag: String?)

data class MediaStream(
    val index: Int,
    val type: String,
    val language: String?,
    val title: String?,
    val codec: String?,
    val isDefault: Boolean,
    val isExternal: Boolean,
    val width: Int? = null,
    val height: Int? = null,
    val bitDepth: Int? = null,
)

data class Chapter(val startSeconds: Double, val name: String?)

/** An intro, recap or credits mark the player can offer to skip. */
data class Segment(val type: String, val startSeconds: Double, val endSeconds: Double)

data class Session(
    val serverUrl: String,
    val userId: String,
    val userName: String,
    val token: String,
    val serverName: String,
)

private fun JSONObject.str(key: String): String? =
    if (has(key) && !isNull(key)) optString(key).ifEmpty { null } else null

private fun JSONObject.int(key: String): Int? = if (has(key) && !isNull(key)) optInt(key) else null
private fun JSONObject.long(key: String): Long? = if (has(key) && !isNull(key)) optLong(key) else null

private fun JSONArray?.objects(): List<JSONObject> =
    if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }

/** Reads the BaseItem shape. Pure, so it is tested against captured JSON. */
fun parseItem(o: JSONObject): Item {
    val user = o.optJSONObject("UserData")
    val images = o.optJSONObject("ImageTags")
    val source = o.optJSONArray("MediaSources").objects().firstOrNull()
    val streams = (o.optJSONArray("MediaStreams") ?: source?.optJSONArray("MediaStreams")).objects()
    return Item(
        id = o.optString("Id"),
        name = o.optString("Name"),
        type = o.optString("Type"),
        overview = o.str("Overview"),
        year = o.int("ProductionYear"),
        seriesId = o.str("SeriesId"),
        seriesName = o.str("SeriesName"),
        seasonId = o.str("SeasonId"),
        seasonName = o.str("SeasonName"),
        indexNumber = o.int("IndexNumber"),
        parentIndexNumber = o.int("ParentIndexNumber"),
        runtimeTicks = o.long("RunTimeTicks"),
        positionTicks = user?.optLong("PlaybackPositionTicks") ?: 0,
        played = user?.optBoolean("Played") ?: false,
        unplayedCount = user?.int("UnplayedItemCount"),
        primaryTag = images?.str("Primary"),
        thumbTag = images?.str("Thumb"),
        backdropTag = o.optJSONArray("BackdropImageTags")?.optString(0)?.ifEmpty { null },
        parentBackdropId = o.str("ParentBackdropItemId"),
        parentBackdropTag = o.optJSONArray("ParentBackdropImageTags")?.optString(0)?.ifEmpty { null },
        seriesPrimaryTag = o.str("SeriesPrimaryImageTag"),
        officialRating = o.str("OfficialRating"),
        communityRating = if (o.has("CommunityRating") && !o.isNull("CommunityRating"))
            o.optDouble("CommunityRating") else null,
        genres = o.optJSONArray("Genres")?.let { a -> (0 until a.length()).map { a.optString(it) } }
            ?: emptyList(),
        collectionType = o.str("CollectionType"),
        isFolder = o.optBoolean("IsFolder"),
        mediaSourceId = source?.str("Id"),
        path = source?.str("Path") ?: o.str("Path"),
        streams = streams.map {
            MediaStream(
                index = it.optInt("Index"),
                type = it.optString("Type"),
                language = it.str("Language"),
                title = it.str("DisplayTitle") ?: it.str("Title"),
                codec = it.str("Codec"),
                isDefault = it.optBoolean("IsDefault"),
                isExternal = it.optBoolean("IsExternal"),
                width = it.int("Width"), height = it.int("Height"), bitDepth = it.int("BitDepth"),
            )
        },
        libraryId = o.str("TopParentId"),
        album = o.str("Album"),
        albumId = o.str("AlbumId") ?: if (o.optString("Type") == "Audio") o.str("ParentId") else null,
        albumArtist = o.str("AlbumArtist"),
        artists = o.optJSONArray("Artists")?.let { a -> (0 until a.length()).map { a.optString(it) } }
            ?: emptyList(),
        favorite = user?.optBoolean("IsFavorite") ?: false,
        parentId = o.str("ParentId"),
        logoTag = images?.str("Logo"),
        people = o.optJSONArray("People").objects().map {
            Person(it.optString("Id"), it.optString("Name"), it.str("Role"), it.str("Type"), it.str("PrimaryImageTag"))
        },
        studios = o.optJSONArray("Studios").objects().map { it.optString("Name") },
        extraType = o.str("ExtraType"),
        childCount = o.int("ChildCount"),
        dateCreated = o.optString("DateCreated").ifEmpty { null },
        chapters = o.optJSONArray("Chapters").objects().map {
            Chapter(it.optLong("StartPositionTicks") / TICKS_PER_SECOND.toDouble(), it.str("Name"))
        },
    )
}

/** `{"Items": [...]}` or a bare array, which /Items/Latest answers with. */
fun parseItems(body: String): List<Item> {
    val trimmed = body.trimStart()
    val array = if (trimmed.startsWith("[")) JSONArray(trimmed)
    else JSONObject(trimmed).optJSONArray("Items")
    return array.objects().map(::parseItem)
}

fun parseSegments(body: String): List<Segment> =
    JSONObject(body).optJSONArray("Items").objects().map {
        Segment(
            type = it.optString("Type"),
            startSeconds = it.optLong("StartTicks") / TICKS_PER_SECOND.toDouble(),
            endSeconds = it.optLong("EndTicks") / TICKS_PER_SECOND.toDouble(),
        )
    }

/** A film in 3D, by the markers its file name or title carries (3D, SBS, OU). */
val Item.is3D: Boolean get() = Regex("""(?i)(\b3d\b|\bh?sbs\b|\bh?ou\b|half[- ]?sbs)""").containsMatchIn(name)

/** Added in the last week and not yet started — Apple's "New" on an Up Next card. */
val Item.isNew: Boolean get() = !played && positionTicks == 0L && dateCreated?.let {
    runCatching { java.time.OffsetDateTime.parse(it).toInstant() }.getOrNull()
        ?.isAfter(java.time.Instant.now().minus(java.time.Duration.ofDays(7)))
} == true
