package app.lumiere.android.cache

import app.lumiere.android.AppState
import app.lumiere.android.api.Item
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The server's answer, or the phone's copy when the server cannot be reached
 * — a title page, a show's seasons and episodes, a folder's contents.
 */
private suspend fun <T> orSaved(fromServer: suspend () -> T, saved: () -> T?): T =
    try {
        fromServer()
    } catch (e: java.io.IOException) {
        withContext(Dispatchers.IO) { saved() } ?: throw e
    }

suspend fun AppState.itemOrSaved(id: String): Item = orSaved(
    { server!!.item(session!!.userId, id) },
    { cache.get(id) ?: downloads.find(id)?.item },
)

suspend fun AppState.seasonsOrSaved(seriesId: String): List<Item> = orSaved(
    { server!!.seasons(session!!.userId, seriesId) }, { cache.seasons(seriesId).ifEmpty { null } })

suspend fun AppState.episodesOrSaved(seriesId: String, seasonId: String?): List<Item> = orSaved(
    { server!!.episodes(session!!.userId, seriesId, seasonId) },
    { cache.episodes(seriesId, seasonId).ifEmpty { null } })

suspend fun AppState.childrenOrSaved(parentId: String): List<Item> = orSaved(
    { server!!.children(session!!.userId, parentId) }, { cache.children(parentId).ifEmpty { null } })
