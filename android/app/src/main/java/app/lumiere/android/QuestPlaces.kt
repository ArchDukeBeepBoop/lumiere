package app.lumiere.android

import android.content.Context

/**
 * Where to Watch, chosen from the Quest's window before a film: the places
 * its theater offers (the quest flavor's Places, kept the same by its test),
 * saved where the theater reads them as it opens.
 */
object QuestPlaces {
    /** Each place's saved name and its label, in the theater's order. */
    val all = listOf(
        "ROOM" to "Your Room", "CINEMA" to "Cinema", "CABIN" to "Cabin", "STATION" to "Space Station",
        "LAKE" to "Lakeside", "CLOUDS" to "Above the Clouds", "MOON" to "The Moon", "SPACE" to "Space", "DARK" to "The Dark",
    )

    private fun prefs(c: Context) = c.getSharedPreferences("quest.screen", Context.MODE_PRIVATE)

    fun chosen(c: Context): Int = all.indexOfFirst { it.first == prefs(c).getString("place", null) }.coerceAtLeast(0)

    fun choose(c: Context, i: Int) { prefs(c).edit().putString("place", all[i].first).apply() }
}
