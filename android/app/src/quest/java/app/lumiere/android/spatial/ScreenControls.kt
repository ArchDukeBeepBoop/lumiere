package app.lumiere.android.spatial

/**
 * The film bar's Seat and Size for the screen now up: neither for 180° and
 * 360° (the picture is the world), no Seat where the screen hangs on your
 * wall, and neither in a place with its own drawn screen, whose seat and
 * screen the picture fixes. A choice remakes the screen ([remake]).
 */
internal fun screenControls(place: ScreenPlace, sphere: Boolean, mounted: Boolean, remake: () -> Unit): FilmBar.Screen? {
    if (sphere) return null
    val drawn = place.where.drawn != null
    val onWall = mounted && place.where == Place.ROOM
    val tv = place.mount != null && place.where == Place.ROOM
    return FilmBar.Screen(
        seats = TheaterGeometry.SEAT_NAMES.takeIf { !drawn && !onWall }, seat = place.seat,
        // In TV Mode the sizes are a TV's, in inches.
        sizes = (if (tv) TvMode.NAMES else ScreenPlace.SIZE_NAMES).takeIf { !drawn }, size = if (tv) place.tvSize else place.size,
        setSeat = { place.seat = it; remake() }, setSize = { if (tv) place.tvSize = it else place.size = it; remake() },
    )
}
