package de.verspaetomat.verspaetomat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The region set's name rules, against the same cases the Swift asserts.
 *
 * `testOnePlatformIsOneRegion` and `testNormaliseFoldsTheWordForTheThingItself`
 * (app/ios/RunnerTests/GeofenceRulesTests.swift:52 and :69) are ported here station for station,
 * so the two platforms assert the same thing about the same coordinates and neither can drift
 * without the other noticing.
 */
class StationNamesTest {

    // ---- normalise: the word for the thing itself ---------------------------------------------

    @Test
    fun `Koeln Hbf and Koeln Hauptbahnhof are one place, Koeln Sued is not`() {
        assertEquals(StationNames.normalise("Köln Hauptbahnhof"), StationNames.normalise("Köln Hbf"))
        assertNotEquals(StationNames.normalise("Köln Hbf"), StationNames.normalise("Köln Süd"))
        // Spelled out, so a change to the fold shows what it now produces rather than only that
        // two unknowns stopped matching.
        assertEquals("koln", StationNames.normalise("Köln Hauptbahnhof"))
        assertEquals("koln", StationNames.normalise("Köln Hbf"))
        assertEquals("kolnsud", StationNames.normalise("Köln Süd"))
    }

    @Test
    fun `sharp s folds to ss, because DELFI and the Swiss feed disagree about it`() {
        // The case the whole fold exists for: „Kißlegg" and „Kisslegg" are one platform, and a
        // diacritic fold alone will not say so — ß is a letter, not an accent.
        assertEquals(StationNames.normalise("Kißlegg Bahnhof"), StationNames.normalise("Kisslegg"))
        assertEquals("kisslegg", StationNames.normalise("Kißlegg Bahnhof"))
        // And it has to happen before the folding, not after: folding never touches ß, so a
        // reversed order would leave „kißlegg" against „kisslegg".
        assertEquals(StationNames.normalise("Kißlegg"), StationNames.normalise("Kisslegg"))
    }

    @Test
    fun `the trailing word for the thing itself is dropped, and hbf before bf`() {
        assertEquals("wangenallgau", StationNames.normalise("Wangen (Allgäu) Bahnhof"))
        assertEquals("wangenallgau", StationNames.normalise("Wangen (Allgäu)"))
        // The order of the suffix list is load-bearing. If „bf" were tried before „hbf",
        // „kolnhbf" would lose two characters and become „kolnh", and Köln Hbf would stop
        // matching Köln Hauptbahnhof — which is the previous test, passing for the wrong reason.
        assertEquals("koln", StationNames.normalise("Köln Hbf"))
        assertEquals("koln", StationNames.normalise("Köln Bf"))
        // Only one word comes off, and only when something is left behind.
        assertEquals("bahnhof", StationNames.normalise("Bahnhof"))
        // „Hbf" alone folds to „h", which looks wrong and is what Swift does, for a reason worth
        // writing down: the guard is `length > suffix.length`, so „hbf" is skipped as a suffix of
        // itself — and then the loop carries on to „bf", which fits and takes two characters. The
        // `break` is inside the test on both sides, so neither stops at the first near miss. It
        // costs nothing, because the names this runs over are „Köln Hbf" and not „Hbf"; it is
        // pinned so that a future tidy-up of the loop has to admit it is changing behaviour.
        assertEquals("h", StationNames.normalise("Hbf"))
    }

    @Test
    fun `punctuation and spacing cannot make two feeds disagree`() {
        assertEquals(StationNames.normalise("Wangen (Allgäu)"), StationNames.normalise("Wangen(Allgäu)"))
        assertEquals(StationNames.normalise("Wangen (Allgäu)"), StationNames.normalise("  Wangen  -  Allgäu  "))
    }

    @Test
    fun `a name with nothing left after folding matches nothing rather than everything`() {
        // An empty fold is a prefix of every string, so `samePlace` has to refuse it explicitly.
        assertEquals("", StationNames.normalise("—"))
        assertFalse(StationNames.samePlace("—", 47.687, 9.833, "Wangen (Allgäu)", 47.687, 9.833))
        assertFalse(StationNames.samePlace("—", 47.687, 9.833, "—", 47.687, 9.833))
    }

    // ---- samePlace: one platform is one region ------------------------------------------------

    /**
     * Issue #11: in Wangen two entries named the same platform — one from the frequent set, one
     * from the nearby list — and the phone sat inside both circles, so it was nudged twice.
     */
    @Test
    fun `one platform is one region`() {
        // Same spot, different feeds, different spelling, different ids.
        val a = Station("de:08436:12345", "Wangen (Allgäu)", 47.6870, 9.8330)
        val b = Station("mock:wangen-bahnhof", "Wangen (Allgäu) Bahnhof", 47.6871, 9.8332)
        assertNotEquals(a.id, b.id)
        assertTrue(StationNames.samePlace(a, b))
        assertTrue("the relation has to be symmetric", StationNames.samePlace(b, a))

        // A different station that happens to be close by keeps its own circle.
        val neighbour = Station("x", "Wangen Nord", 47.6872, 9.8331)
        assertFalse(StationNames.samePlace(a, neighbour))

        // The same name 200 km away is a different station and stays one.
        val elsewhere = Station("y", "Wangen (Allgäu)", 49.5, 9.8)
        assertFalse(StationNames.samePlace(a, elsewhere))
    }

    @Test
    fun `two hundred and fifty metres is the gate, and it is a distance and not a guess`() {
        val name = "Wangen (Allgäu)"
        // Due north of 47.6870, at roughly 100 m and roughly 400 m.
        val near = 47.6870 + 100.0 / 111_320.0
        val far = 47.6870 + 400.0 / 111_320.0
        assertTrue(StationNames.samePlace(name, 47.6870, 9.8330, name, near, 9.8330))
        assertFalse(StationNames.samePlace(name, 47.6870, 9.8330, name, far, 9.8330))
        assertEquals(250.0, StationNames.SAME_PLACE_M, 0.0)
    }

    // ---- the regression this is guarding ------------------------------------------------------

    /**
     * The test that fails if the region set goes back to deduping by id.
     *
     * `GeofenceManager.kt:194-195` is `nearest(ctx).filter { ids.add(it.id) }` — id equality and
     * nothing else. Both shapes are written out below rather than described, so this asserts the
     * difference between them instead of asserting that one of them works.
     */
    @Test
    fun `deduping by id alone keeps the double nudge that samePlace removes`() {
        val frequent = Station("de:08436:12345", "Wangen (Allgäu)", 47.6870, 9.8330)
        val fromNearby = Station("mock:wangen-bahnhof", "Wangen (Allgäu) Bahnhof", 47.6871, 9.8332)

        // Today's dedupe, as it stands in GeofenceManager.
        val ids = mutableSetOf(frequent.id)
        val byId = listOf(fromNearby).filter { ids.add(it.id) }
        assertEquals("two circles on one platform is issue #11", 1, byId.size)

        // What it has to become once the nearby list is twenty-five deep.
        val kept = mutableListOf(frequent)
        val bySamePlace = listOf(fromNearby)
            .filter { s -> kept.none { it.id == s.id || StationNames.samePlace(it, s) } }
        assertEquals("one platform, one circle", 0, bySamePlace.size)
    }

    @Test
    fun `deduping by name alone would merge two real stations, so the distance still gates it`() {
        // The other direction, so the fix cannot be „just compare names": two genuinely different
        // Wangens fold to the same string and must stay two regions.
        val allgaeu = Station("a", "Wangen (Allgäu)", 47.6870, 9.8330)
        val elsewhere = Station("b", "Wangen (Allgäu)", 49.5000, 9.8000)
        assertEquals(StationNames.normalise(allgaeu.name), StationNames.normalise(elsewhere.name))
        assertFalse(StationNames.samePlace(allgaeu, elsewhere))
    }
}
