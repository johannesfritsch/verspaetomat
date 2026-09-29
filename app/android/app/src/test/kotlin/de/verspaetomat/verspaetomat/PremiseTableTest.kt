package de.verspaetomat.verspaetomat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The station premises (issue #64): the shared fixture the server rendered (`outlines.rs`,
 * `fixture_set`), read to the numbers Dart and Swift assert too; and the fence plan.
 */
class PremiseTableTest {
    private val fixture = File(Repo.root, "app/test/fixtures/umrisse-fixture.bin").readBytes()

    @Test
    fun `the fixture reads to the server's numbers`() {
        val t = PremiseTable.parse(fixture)
        assertEquals(1_790_700_677L, t.version)
        assertEquals(1_790_640_000L, t.generated)
        assertEquals(listOf(3L, 17L, 4711L), t.entries.keys.sorted())
        assertEquals(listOf(120.0), t.entry("vs:3")!!.touch.map { it.radius })
        val koeln = t.entry("vs:17")!!
        assertEquals(50.943, koeln.ring.lat, 1e-9)
        assertEquals(6.9587, koeln.ring.lon, 1e-9)
        assertEquals(429.0, koeln.ring.radius, 0.0)
        assertEquals(listOf(150.0, 139.0, 135.0), koeln.touch.map { it.radius })
        assertEquals(50.9435, koeln.touch[0].lat, 1e-9)
        val big = t.entry("vs:4711")!!
        assertEquals(1000.0, big.ring.radius, 0.0)
        assertEquals(6, big.touch.size)
        assertEquals(125.0, big.touch.last().radius, 0.0)
        assertNull(t.entry("vs:4"))
        assertNull("a MOTIS id has no premise", t.entry("de-DELFI_de:05315:11201"))
    }

    @Test
    fun `a damaged copy is refused whole`() {
        val flipped = fixture.copyOf().also { it[it.size - 1] = (it[it.size - 1].toInt() xor 1).toByte() }
        assertThrows(PremiseTable.Refused::class.java) { PremiseTable.parse(flipped) }
        assertThrows(PremiseTable.Refused::class.java) { PremiseTable.parse(fixture.copyOf(fixture.size - 1)) }
        val magic = fixture.copyOf().also { it[0] = 0x41 }
        assertThrows(PremiseTable.Refused::class.java) { PremiseTable.parse(magic) }
    }

    private fun st(n: Int) = Station("vs:$n", "S$n", 50 + n * 0.01, 7.0)
    private fun entry(touches: Int) =
        PremiseEntry(PremiseCircle(50.5, 7.5, 450.0), (0 until touches).map { PremiseCircle(50.5 + it * 0.001, 7.5, 130.0) })

    @Test
    fun `touch points for a premise, the 300 m ring without, whole stations and never past 99`() {
        val plan = PremiseFences.plan(listOf(st(1), st(2)), { if (it == "vs:1") entry(3) else null }, 300f)
        assertEquals(listOf("touch:vs:1:1", "touch:vs:1:2", "touch:vs:1:3", "station:vs:2"), plan.map { it.id })
        assertEquals(300f, plan.last().radius)
        val full = PremiseFences.plan((1..40).map(::st), { entry(6) }, 300f)
        assertTrue(full.size <= PremiseFences.MAX_FENCES)
        assertEquals("16 whole stations of six", 96, full.size)
        assertEquals(16, full.map { it.stationId }.distinct().size)
    }

    @Test
    fun `a touch point names its station`() {
        assertEquals("vs:17", PremiseFences.stationId("touch:vs:17:2"))
        assertEquals("de-DELFI_de:05315:11201", PremiseFences.stationId("touch:de-DELFI_de:05315:11201:1"))
        assertNull(PremiseFences.stationId("station:vs:17"))
    }
}
