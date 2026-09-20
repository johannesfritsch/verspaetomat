package de.verspaetomat.verspaetomat

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The reader, against bytes written from the format spec rather than from itself where that is
 * possible — and against every way a file can be plausible and wrong.
 *
 * Mirrors `app/test/station_extract_test.dart` case for case, so a change to the format shows up
 * in both languages or in neither.
 */
class StationExtractTest {

    @Test
    fun `an extract reads back as the stations it was written from`() {
        val x = StationExtract.decode(buildVst(SAMPLE_STATIONS, version = 12))

        assertEquals(1, x.format)
        assertEquals(32, x.headerLen)
        assertEquals(20, x.recordLen)
        assertEquals(12L, x.tableVersion)
        assertEquals(FIXTURE_GENERATED_AT_SECS, x.generatedAt)
        assertEquals(5, x.count)
        assertEquals(182, x.byteLength)

        assertEquals(listOf(3L, 11L, 12L, 20L, 21L), (0 until x.count).map { x.id(it) })
        assertEquals(
            listOf("Köln Hbf", "Kißlegg Bahnhof", "Wangen im Allgäu", "Neustadt", "Neustadt"),
            (0 until x.count).map { x.name(it) },
        )
        assertEquals(listOf(3, 2, 2, 1, 1), (0 until x.count).map { x.rank(it) })
        assertEquals("vs:3", "vs:" + x.id(0))

        // Micro-degrees, so six decimals survive and nothing beyond them is claimed.
        assertEquals(50.9430, x.lat(0), 5e-7)
        assertEquals(6.9586, x.lon(0), 5e-7)
        assertEquals(49.3500, x.lat(4), 5e-7)

        // `looks_like_station`, baked into byte 13 at build time. Not trivially constant: record 1
        // carries the bit and record 2 does not.
        assertTrue("Köln Hbf", x.namedLikeStation(0))
        assertTrue("Kißlegg Bahnhof", x.namedLikeStation(1))
        assertFalse("Wangen im Allgäu", x.namedLikeStation(2))
        assertNotEquals(x.flags(1), x.flags(2))
    }

    @Test
    fun `two records with the same name share one slice of the blob`() {
        val bytes = buildVst(SAMPLE_STATIONS)
        val x = StationExtract.decode(bytes)
        assertEquals("Neustadt", x.name(3))
        assertEquals("Neustadt", x.name(4))
        // 'Köln Hbf' 9 + 'Kißlegg Bahnhof' 16 + 'Wangen im Allgäu' 17 + 'Neustadt' 8 = 50 bytes,
        // written once each. A blob that stored the duplicate would be eight bytes longer.
        assertEquals(50, x.blobLen)
        assertEquals(32 + 5 * 20 + 50, bytes.size)
    }

    @Test
    fun `a grown header and a grown record still read, because the lengths come out of the file`() {
        // The additive rule written for a binary file: `format` stays 1, a new header field raises
        // `header_len`, a new record field raises `record_len`, and a phone already in the field
        // keeps reading. This is the test that catches a hardcoded 32 or 20 anywhere — in the
        // record stride, in the blob offset, or in the range the checksum is taken over.
        val x = StationExtract.decode(buildVst(SAMPLE_STATIONS, headerLen = 40, recordLen = 24))
        assertEquals(40, x.headerLen)
        assertEquals(24, x.recordLen)
        assertEquals(listOf(3L, 11L, 12L, 20L, 21L), (0 until x.count).map { x.id(it) })
        assertEquals("Köln Hbf", x.name(0))
        assertEquals("Neustadt", x.name(4))
        assertEquals(50.9430, x.lat(0), 5e-7)
        assertEquals(210, x.byteLength)
    }

    @Test
    fun `byte 15 is reserved, and a reader that asserts it is zero would refuse the next format`() {
        // Set byte 15 of EVERY record, before the checksum is taken — which is what `patchBody`
        // exists for and what `flipByteAfterCrc` cannot do.
        val x = StationExtract.decode(
            buildVst(SAMPLE_STATIONS, patchBody = { body ->
                for (i in 0 until 5) body[i * 20 + 15] = 0xAB.toByte()
                body
            }),
        )
        assertEquals(5, x.count)
        assertEquals("Köln Hbf", x.name(0))
        assertEquals(listOf(3L, 11L, 12L, 20L, 21L), (0 until x.count).map { x.id(it) })
    }

    // ---- a file that is not the file it claims to be is refused whole ------------------------

    private fun refuses(what: String, bytes: ByteArray, because: String) {
        val e = try {
            StationExtract.decode(bytes)
            null
        } catch (e: VstFormatException) {
            e
        }
        assertTrue("$what: expected a VstFormatException", e != null)
        assertTrue(
            "$what: the message was '${e!!.message}', which does not mention '$because'",
            e.message!!.contains(because),
        )
    }

    /** Overwrite a header field after the file is built, which no knob on the builder can do. */
    private fun patchHeader(bytes: ByteArray, write: (ByteBuffer) -> Unit): ByteArray {
        val out = bytes.copyOf()
        write(ByteBuffer.wrap(out).order(ByteOrder.LITTLE_ENDIAN))
        return out
    }

    @Test
    fun `a wrong magic is refused`() =
        refuses("magic", buildVst(SAMPLE_STATIONS, magic = byteArrayOf(0x56, 0x53, 0x54, 0x4E)), "magic")

    @Test
    fun `a format this reader does not know is refused`() =
        refuses("format", buildVst(SAMPLE_STATIONS, format = 2), "format 2")

    @Test
    fun `a header_len shorter than the format allows is refused`() =
        refuses("header_len 31", patchHeader(buildVst(SAMPLE_STATIONS)) { it.putShort(6, 31) }, "header_len 31")

    @Test
    fun `a record_len shorter than the format allows is refused`() =
        refuses("record_len 19", patchHeader(buildVst(SAMPLE_STATIONS)) { it.putInt(12, 19) }, "record_len 19")

    @Test
    fun `an extract of nothing is refused`() =
        refuses("count 0", buildVst(SAMPLE_STATIONS, countOverride = 0), "an extract of nothing")

    @Test
    fun `a count that overruns the buffer is refused`() =
        refuses("count 9", buildVst(SAMPLE_STATIONS, countOverride = 9), "bytes")

    @Test
    fun `a blob shorter than the names in it is refused`() =
        refuses("blob_len 20", buildVst(SAMPLE_STATIONS, blobLenOverride = 20), "bytes")

    @Test
    fun `a truncated file is refused`() =
        refuses("truncated", buildVst(SAMPLE_STATIONS, truncateTo = 90), "bytes")

    @Test
    fun `a file shorter than a header is refused`() =
        refuses("12 bytes", buildVst(SAMPLE_STATIONS, truncateTo = 12), "shorter than the header")

    @Test
    fun `a flipped byte after the checksum was taken is refused`() =
        refuses("flipped byte 40", buildVst(SAMPLE_STATIONS, flipByteAfterCrc = 40), "checksum")

    @Test
    fun `a name that starts outside the blob is refused`() = refuses(
        "name_off 9999",
        buildVst(SAMPLE_STATIONS, patchBody = { body ->
            // Record 0's `name_off` at body offset 16, pushed past the end of the blob. The length
            // still adds up and the checksum still matches; only the per-record pass catches it.
            ByteBuffer.wrap(body).order(ByteOrder.LITTLE_ENDIAN).putInt(16, 9999)
            body
        }),
        "outside the blob",
    )

    @Test
    fun `a name of no length at all is refused`() = refuses(
        "name_len 0",
        buildVst(SAMPLE_STATIONS, patchBody = { body -> body[14] = 0; body }),
        "no name",
    )

    // ---- the checksum -------------------------------------------------------------------------

    @Test
    fun `the checksum is the ordinary zlib CRC-32, and the fixture is the Dart's fixture`() {
        // "123456789" → 0xCBF43926, the standard check value for CRC-32/ISO-HDLC.
        val check = java.util.zip.CRC32().apply { update("123456789".toByteArray()) }.value
        assertEquals(0xCBF43926L, check)

        // And the stronger pin: these bytes came out of a run of `app/test/support/vst_fixture.dart`
        // over `kSampleStations`, printed as hex. Asserting the whole file rather than only its
        // checksum pins the blob sharing, the baked flags byte, the micro-degree rounding and the
        // zero-filled growth padding — so the two fixtures are tied to each other and not each to
        // itself.
        assertEquals(DART_FIXTURE_PLAIN, buildVst(SAMPLE_STATIONS).toHex())
        assertEquals(DART_FIXTURE_GROWN, buildVst(SAMPLE_STATIONS, headerLen = 40, recordLen = 24).toHex())

        val x = StationExtract.decode(buildVst(SAMPLE_STATIONS))
        assertEquals(0xca8b619cL, x.crc32)
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    companion object {
        private const val DART_FIXTURE_PLAIN =
            "5653535401002000050000001400000032000000209bac6a0c0000009c618bca" +
                "0300000018540903082e6a0003010900000000000b000000283dd90204f19600" +
                "02011000090000000c000000e8a6d702dcec9500020011001900000014000000" +
                "e03d2a0380cba400010008002a000000150000007005f102e0347c0001000800" +
                "2a0000004bc3b66c6e204862664b69c39f6c656767204261686e686f6657616e" +
                "67656e20696d20416c6c67c3a4754e65757374616474"
        private const val DART_FIXTURE_GROWN =
            "5653535401002800050000001800000032000000209bac6a0c0000005575c18a" +
                "00000000000000000300000018540903082e6a00030109000000000000000000" +
                "0b000000283dd90204f196000201100009000000000000000c000000e8a6d702" +
                "dcec950002001100190000000000000014000000e03d2a0380cba40001000800" +
                "2a00000000000000150000007005f102e0347c00010008002a00000000000000" +
                "4bc3b66c6e204862664b69c39f6c656767204261686e686f6657616e67656e20" +
                "696d20416c6c67c3a4754e65757374616474"
    }
}
