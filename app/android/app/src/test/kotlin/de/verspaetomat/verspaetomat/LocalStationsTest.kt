package de.verspaetomat.verspaetomat

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The seam the geofence layer calls, and its three answers.
 *
 * `null` means „could not look up" — missing, damaged, truncated, implausibly small. A non-null
 * answer with no stations means „there is genuinely nothing here". The caller keeps its registered
 * set on the first and drops it on the second, and issue #31 is the record of what treating them
 * alike costs. That distinction is the whole point of this file, so it gets its own tests.
 */
class LocalStationsTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private val warnings = mutableListOf<String>()

    private fun nearby(file: File, lat: Double = 50.9430, lon: Double = 6.9586, limit: Int = 25) =
        LocalStations.nearby(file, lat, lon, limit) { warnings.add(it) }

    @Test
    fun `a missing file is a null answer and not a throw`() {
        val answer = nearby(File(tmp.root, "stations/stations.vst"))
        assertNull(answer)
        assertTrue(warnings.single(), warnings.single().contains("could not be read"))
    }

    @Test
    fun `a damaged file is a null answer`() {
        val f = tmp.newFile("stations.vst")
        f.writeBytes(buildVst(plausibleTable(), flipByteAfterCrc = 200))
        assertNull(nearby(f))
        assertTrue(warnings.single(), warnings.single().contains("checksum"))
    }

    @Test
    fun `a truncated file is a null answer`() {
        val f = tmp.newFile("stations.vst")
        f.writeBytes(buildVst(plausibleTable(), truncateTo = 5_000))
        assertNull(nearby(f))
        assertTrue(warnings.single(), warnings.single().contains("bytes"))
    }

    @Test
    fun `a file with fewer stations than a real table is a null answer`() {
        // `StationStore.minPlausibleCount` on this side: the table has held over 7,000 stations
        // since #37, so anything this small is a mistake upstream, not a smaller Germany.
        val f = tmp.newFile("stations.vst")
        f.writeBytes(buildVst(plausibleTable(count = VstFormat.MIN_PLAUSIBLE_COUNT - 1)))
        assertNull(nearby(f))
        assertTrue(warnings.single(), warnings.single().contains("holds only 999 stations"))
    }

    @Test
    fun `a plausible file answers, and the answer carries its own scope`() {
        val f = tmp.newFile("stations.vst")
        f.writeBytes(buildVst(plausibleTable()))
        val a = nearby(f)!!
        assertTrue(warnings.isEmpty())
        assertTrue(a.stations.isNotEmpty())
        assertTrue(a.complete)
        assertEquals(a.stations.maxOf { it.distanceM }, a.searchRadiusM)
        assertTrue(a.stations.all { it.distanceM <= VstFormat.NEARBY_MAX_M })
    }

    @Test
    fun `an empty answer is not a failed one`() {
        // Over the extract that actually ships: the Atlantic really has no station within fifty
        // kilometres, so this is the case the caller must not confuse with a read that failed.
        val a = nearby(Repo.extractFile, lat = 48.0, lon = -5.0)
        assertNotNull("an unreadable extract at ${Repo.extractFile}", a)
        assertTrue(a!!.stations.isEmpty())
        assertFalse(a.complete)
        assertEquals(0, a.searchRadiusM)
        assertTrue(warnings.isEmpty())
    }

    @Test
    fun `the shipped extract answers where there is something to answer`() {
        val a = nearby(Repo.extractFile)!!
        assertTrue(a.complete)
        assertEquals(25, a.stations.size)
        assertTrue(a.stations.first().name, a.stations.first().name.contains("Köln"))
        assertTrue(a.stations.first().id.startsWith("vs:"))
        assertEquals(a.stations.maxOf { it.distanceM }, a.searchRadiusM)
    }
}
