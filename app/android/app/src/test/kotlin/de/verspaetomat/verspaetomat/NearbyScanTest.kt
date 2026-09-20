package de.verspaetomat.verspaetomat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The four rules that decide a nearby answer, one table each, over distances that are round
 * numbers of metres so a failure names the rule rather than the arithmetic.
 *
 * `nearby_order` (backend/src/train/transitous.rs:492-494) is
 * `(distance / 300, -rank, named ? 0 : 1, distance)`, with the record index appended
 * (app/lib/stations/station_index.dart:70). Every expected answer below was computed by a
 * separate implementation of the scan rather than by this one.
 */
class NearbyScanTest {

    /** Due north of the probe, so the offsets below are metres along a meridian. */
    private val probeLat = 50.0
    private val probeLon = 10.0

    private fun scan(stations: List<VstStation>, limit: Int = 25): NearbyAnswer =
        StationExtract.decode(buildVst(stations)).nearby(probeLat, probeLon, limit)

    private fun ids(a: NearbyAnswer): List<String> = a.stations.map { it.id }

    @Test
    fun `inside one 300 m band the better station wins, beyond it distance decides again`() {
        // 60 m, 250 m, 400 m. The first two share band 0, so the Hauptbahnhof at 250 m comes
        // before the market square at 60 m; the one at 400 m is in band 1 and comes last however
        // good it is.
        val a = scan(
            listOf(
                VstStation(1, "Marktplatz", 50.000540, 10.0, 1),
                VstStation(2, "Testhausen Hbf", 50.002250, 10.0, 3),
                VstStation(3, "Weitweg Hbf", 50.003600, 10.0, 3),
            ),
        )
        assertEquals(listOf("vs:2", "vs:1", "vs:3"), ids(a))
        assertEquals(listOf(250, 60, 400), a.stations.map { it.distanceM })
        // The answer's own scope: how far it reaches, not how far the first station is.
        assertEquals(400, a.searchRadiusM)
        assertTrue(a.complete)
    }

    @Test
    fun `inside one band the rank ladder decides`() {
        val a = scan(
            listOf(
                VstStation(1, "Ahausen Bahnhof", 50.000540, 10.0, 1),
                VstStation(2, "Behausen Bahnhof", 50.000900, 10.0, 3),
            ),
        )
        assertEquals(listOf("vs:2", "vs:1"), ids(a))
    }

    @Test
    fun `inside one band, at the same rank, the name that says Bahnhof decides`() {
        // The flag is read out of record byte 13 and never re-derived from the name: this is the
        // tiebreak that puts the station a passenger can read off the building first.
        val a = scan(
            listOf(
                VstStation(1, "Cestadt, Markt", 50.000540, 10.0, 2),
                VstStation(2, "Cestadt Bahnhof", 50.000900, 10.0, 2),
            ),
        )
        assertEquals(listOf("vs:2", "vs:1"), ids(a))
    }

    @Test
    fun `everything else equal, the nearer station decides`() {
        val a = scan(
            listOf(
                VstStation(1, "Dorf, Markt", 50.000900, 10.0, 2),
                VstStation(2, "Esel, Markt", 50.000540, 10.0, 2),
            ),
        )
        assertEquals(listOf("vs:2", "vs:1"), ids(a))
    }

    @Test
    fun `an exact tie is broken by the record index, which is ascending id order`() {
        // Two platforms on one coordinate. Without this the order is whatever the sort happens to
        // leave behind — and the region set cuts this list, so a tie that straddles the cut
        // decides which of the two gets a geofence.
        val a = scan(
            listOf(
                VstStation(1, "Gleis 1, Bahnsteig", 50.000540, 10.0, 2),
                VstStation(2, "Gleis 2, Bahnsteig", 50.000540, 10.0, 2),
            ),
        )
        assertEquals(listOf("vs:1", "vs:2"), ids(a))
        assertEquals(listOf(60, 60), a.stations.map { it.distanceM })
        // And the same order once it is re-sorted for region selection.
        assertEquals(listOf("vs:1", "vs:2"), a.nearestFirst().map { it.id })
    }

    @Test
    fun `the cut happens before the rank sort, so a limit never drops a nearer station`() {
        // Three market squares at 60, 100 and 150 m and a Hauptbahnhof at 250 m. All four are in
        // band 0, so ranking first would put the Hauptbahnhof at the top and a limit of three
        // would throw away the station 150 m away in its favour. The cut is nearest-first.
        val table = listOf(
            VstStation(1, "Eins, Markt", 50.000540, 10.0, 1),
            VstStation(2, "Zwei, Markt", 50.000900, 10.0, 1),
            VstStation(3, "Drei, Markt", 50.001350, 10.0, 1),
            VstStation(4, "Vier Hbf", 50.002250, 10.0, 3),
        )
        val three = scan(table, limit = 3)
        assertEquals(listOf("vs:1", "vs:2", "vs:3"), ids(three))
        assertEquals(150, three.searchRadiusM)

        val four = scan(table, limit = 4)
        assertEquals(listOf("vs:4", "vs:1", "vs:2", "vs:3"), ids(four))
        assertEquals(250, four.searchRadiusM)
    }

    @Test
    fun `nothing within fifty kilometres is an empty answer, and an empty answer is never complete`() {
        val a = scan(listOf(VstStation(1, "Ferne, Markt", 50.5, 10.0, 1)))
        assertTrue(a.stations.isEmpty())
        assertFalse(a.complete)
        assertEquals(0, a.searchRadiusM)
    }

    @Test
    fun `a limit larger than the table returns the table`() {
        val a = scan(listOf(VstStation(1, "Eins, Markt", 50.000540, 10.0, 1)), limit = 25)
        assertEquals(1, a.stations.size)
        assertEquals(60, a.searchRadiusM)
        assertTrue(a.complete)
    }

    @Test
    fun `nearestFirst is distance ascending, not the ranked order`() {
        val a = scan(
            listOf(
                VstStation(1, "Marktplatz", 50.000540, 10.0, 1),
                VstStation(2, "Testhausen Hbf", 50.002250, 10.0, 3),
            ),
        )
        assertEquals(listOf("vs:2", "vs:1"), ids(a))
        assertEquals(listOf("vs:1", "vs:2"), a.nearestFirst().map { it.id })
    }

    @Test
    fun `a station standing on its own coordinate finds itself at nought metres`() {
        val a = scan(listOf(VstStation(1, "Nullpunkt Hbf", probeLat, probeLon, 3)))
        assertEquals(0, a.stations.single().distanceM)
        assertEquals(0, a.searchRadiusM)
        assertTrue(a.complete)
    }
}
