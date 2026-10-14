package app.lumiere.android.cache

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import app.lumiere.android.api.Item
import app.lumiere.android.api.parseItem
import org.json.JSONObject

/**
 * The phone's own copy of the video libraries: every item as the server sent
 * it, plus the few columns the grid sorts and filters on. Filled once, then
 * kept current by [CacheSync] from the server's change feed — the Mac's
 * arrangement, on the phone. Grids open from it at once, and everything
 * browses with no server in reach.
 */
class LibraryCache(context: Context) : SQLiteOpenHelper(context, "library-cache.db", null, 1) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""CREATE TABLE item (id TEXT PRIMARY KEY, library_id TEXT, type TEXT, name TEXT,
            sort_name TEXT, date_created TEXT, year INTEGER, last_played TEXT, played INTEGER,
            favorite INTEGER, position INTEGER, extra INTEGER, genres TEXT, series_id TEXT, parent_id TEXT,
            season INTEGER, episode INTEGER, json TEXT NOT NULL)""")
        db.execSQL("CREATE INDEX item_library ON item(library_id, sort_name)")
        db.execSQL("CREATE INDEX item_series ON item(series_id, season, episode)")
        db.execSQL("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
    }

    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) = Unit

    fun meta(key: String): String? = readableDatabase.rawQuery("SELECT value FROM meta WHERE key = ?", arrayOf(key))
        .use { if (it.moveToFirst()) it.getString(0) else null }

    fun setMeta(key: String, value: String?) {
        if (value == null) writableDatabase.delete("meta", "key = ?", arrayOf(key))
        else writableDatabase.insertWithOnConflict("meta", null,
            ContentValues().apply { put("key", key); put("value", value) }, SQLiteDatabase.CONFLICT_REPLACE)
    }

    /** Writes items as the server sent them, filed under [libraryId] (or their own TopParentId). */
    fun upsert(items: List<JSONObject>, libraryId: String? = null) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            for (o in items) {
                val user = o.optJSONObject("UserData")
                val genres = o.optJSONArray("Genres")?.let { a -> (0 until a.length()).joinToString("|") { a.optString(it) } }
                db.insertWithOnConflict("item", null, ContentValues().apply {
                    put("id", o.optString("Id"))
                    put("library_id", libraryId ?: o.optString("TopParentId").ifEmpty { null })
                    put("type", o.optString("Type"))
                    put("name", o.optString("Name"))
                    put("sort_name", o.optString("SortName").ifEmpty { o.optString("Name") }.lowercase())
                    put("date_created", o.optString("DateCreated"))
                    put("year", if (o.has("ProductionYear") && !o.isNull("ProductionYear")) o.optInt("ProductionYear") else null)
                    put("last_played", user?.optString("LastPlayedDate")?.ifEmpty { null })
                    put("played", if (user?.optBoolean("Played") == true) 1 else 0)
                    put("favorite", if (user?.optBoolean("IsFavorite") == true) 1 else 0)
                    put("position", user?.optLong("PlaybackPositionTicks") ?: 0L)
                    put("extra", if (o.has("ExtraType") && !o.isNull("ExtraType")) 1 else 0)
                    put("genres", genres?.let { "|$it|" })
                    put("series_id", o.optString("SeriesId").ifEmpty { null })
                    put("parent_id", o.optString("ParentId").ifEmpty { null })
                    put("season", if (o.has("ParentIndexNumber") && !o.isNull("ParentIndexNumber")) o.optInt("ParentIndexNumber") else null)
                    put("episode", if (o.has("IndexNumber") && !o.isNull("IndexNumber")) o.optInt("IndexNumber") else null)
                    put("json", o.toString())
                }, SQLiteDatabase.CONFLICT_REPLACE)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun remove(ids: List<String>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            ids.forEach { db.delete("item", "id = ?", arrayOf(it)) }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun clearLibrary(libraryId: String) = writableDatabase.delete("item", "library_id = ?", arrayOf(libraryId))

    fun count(libraryId: String): Int = readableDatabase.rawQuery(
        "SELECT count(*) FROM item WHERE library_id = ?", arrayOf(libraryId)).use { it.moveToFirst(); it.getInt(0) }

    fun get(id: String): Item? = readableDatabase.rawQuery("SELECT json FROM item WHERE id = ?", arrayOf(id))
        .use { if (it.moveToFirst()) parseItem(JSONObject(it.getString(0))) else null }

    /**
     * A page of a library's grid, with the grid's own sorts and filters, so
     * the screen reads the same whether the answer came from here or the server.
     */
    fun page(
        libraryId: String?, start: Int, limit: Int, sortBy: String, descending: Boolean,
        types: List<String>, genre: String? = null, unwatched: Boolean = false, favourites: Boolean = false,
        from: String? = null, search: String? = null,
    ): List<Item> {
        val where = mutableListOf("extra = 0", "type IN (${types.joinToString(",") { "?" }})")
        val args = types.toMutableList()
        libraryId?.let { where += "library_id = ?"; args += it }
        genre?.let { where += "genres LIKE ?"; args += "%|$it|%" }
        if (unwatched) where += "played = 0"
        if (favourites) where += "favorite = 1"
        from?.let { where += "sort_name >= ?"; args += it.lowercase() }
        search?.takeIf { it.isNotBlank() }?.let { where += "name LIKE ?"; args += "%$it%" }
        val column = when (sortBy) {
            "DateCreated" -> "date_created"
            "ProductionYear" -> "year"
            "DatePlayed" -> "last_played"
            else -> "sort_name"
        }
        val order = "$column ${if (descending) "DESC" else "ASC"}, sort_name, id"
        return readableDatabase.rawQuery(
            "SELECT json FROM item WHERE ${where.joinToString(" AND ")} ORDER BY $order LIMIT $limit OFFSET $start",
            args.toTypedArray(),
        ).use { c -> buildList { while (c.moveToNext()) add(parseItem(JSONObject(c.getString(0)))) } }
    }

    /** A show's seasons, in order. */
    fun seasons(seriesId: String): List<Item> = rows(
        "SELECT json FROM item WHERE series_id = ? AND type = 'Season' ORDER BY episode, sort_name", seriesId)

    /** A show's episodes — one season's, or all — in order. */
    fun episodes(seriesId: String, seasonId: String?): List<Item> =
        if (seasonId == null) rows("SELECT json FROM item WHERE series_id = ? AND type = 'Episode' AND extra = 0 " +
            "ORDER BY season, episode, sort_name", seriesId)
        else rows("SELECT json FROM item WHERE parent_id = ? AND type = 'Episode' AND extra = 0 " +
            "ORDER BY episode, sort_name", seasonId)

    /** What is inside a folder or collection. */
    fun children(parentId: String): List<Item> = rows(
        "SELECT json FROM item WHERE parent_id = ? ORDER BY sort_name", parentId)

    private fun rows(sql: String, vararg args: String): List<Item> = readableDatabase.rawQuery(sql, args)
        .use { c -> buildList { while (c.moveToNext()) add(parseItem(JSONObject(c.getString(0)))) } }

    /** Continue Watching from the copy: started, not finished, most recent first. */
    fun resume(limit: Int = 24): List<Item> = readableDatabase.rawQuery(
        "SELECT json FROM item WHERE position > 0 AND played = 0 AND extra = 0 ORDER BY last_played DESC LIMIT $limit", null,
    ).use { c -> buildList { while (c.moveToNext()) add(parseItem(JSONObject(c.getString(0)))) } }
}
