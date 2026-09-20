package de.verspaetomat.verspaetomat

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import java.util.zip.CRC32

/**
 * The Kotlin twin of `app/test/support/vst_fixture.dart`: it writes the bytes
 * `stations::extract::render` writes, so the reader is tested against files it did not produce
 * itself.
 *
 * Same knobs and same names as the Dart, deliberately, including [patchBody] — which is the only
 * way to change a record *before* the checksum is taken, and therefore the only way to write a
 * grown-but-valid file.
 */
data class VstStation(
    val id: Int,
    val name: String,
    val lat: Double,
    val lon: Double,
    val rank: Int,
    /** Defaults to what `looks_like_station` says, which is what the builder bakes in. */
    val flags: Int? = null,
)

/**
 * `DateTime.utc(2026, 9, 18, 2)` in unix seconds — the Dart fixture's default
 * (vst_fixture.dart:72), so a file built here and a file built there are the same bytes and the
 * pin in [StationExtractTest] means something. Taken from a run of the Dart, not from arithmetic.
 */
const val FIXTURE_GENERATED_AT_SECS = 1_789_696_800L

fun buildVst(
    stations: List<VstStation>,
    version: Int = 12,
    generatedAtSecs: Long = FIXTURE_GENERATED_AT_SECS,
    format: Int = 1,
    headerLen: Int = 32,
    recordLen: Int = 20,
    magic: ByteArray = VstFormat.magic(),
    countOverride: Int? = null,
    blobLenOverride: Int? = null,
    /** Applied to `records + blob` BEFORE the CRC is computed — vst_fixture.dart:62. */
    patchBody: ((ByteArray) -> ByteArray)? = null,
    flipByteAfterCrc: Int? = null,
    truncateTo: Int? = null,
): ByteArray {
    val blob = ByteArrayOutputStream()
    val offsets = LinkedHashMap<String, Int>()
    val records = ByteArrayOutputStream()
    for (s in stations) {
        val name = s.name.toByteArray(StandardCharsets.UTF_8)
        // The first occurrence in record order wins the slice; a repeat points at it.
        val off = offsets.getOrPut(s.name) {
            val at = blob.size()
            blob.write(name)
            at
        }
        val r = ByteBuffer.allocate(recordLen).order(ByteOrder.LITTLE_ENDIAN)
        r.putInt(0, s.id)
        r.putInt(4, Math.round(s.lat * 1_000_000.0).toInt())
        r.putInt(8, Math.round(s.lon * 1_000_000.0).toInt())
        r.put(12, s.rank.toByte())
        r.put(13, (s.flags ?: if (looksLikeStation(s.name)) VstFormat.FLAG_LOOKS_LIKE_STATION else 0).toByte())
        r.put(14, name.size.toByte())
        r.put(15, 0)
        r.putInt(16, off)
        records.write(r.array())
    }
    val blobBytes = blob.toByteArray()
    var body = records.toByteArray() + blobBytes
    if (patchBody != null) body = patchBody(body)

    val header = ByteBuffer.allocate(headerLen).order(ByteOrder.LITTLE_ENDIAN)
    header.put(0, magic, 0, 4)
    header.putShort(4, format.toShort())
    header.putShort(6, headerLen.toShort())
    header.putInt(8, countOverride ?: stations.size)
    header.putInt(12, recordLen)
    header.putInt(16, blobLenOverride ?: blobBytes.size)
    header.putInt(20, generatedAtSecs.toInt())
    header.putInt(24, version)
    header.putInt(28, CRC32().apply { update(body) }.value.toInt())

    var out = header.array() + body
    if (flipByteAfterCrc != null) out[flipByteAfterCrc] = (out[flipByteAfterCrc].toInt() xor 0xFF).toByte()
    if (truncateTo != null) out = out.copyOf(truncateTo)
    return out
}

/**
 * `train::transitous::looks_like_station` (backend/src/train/transitous.rs:498-501), ported into
 * the **test** source set only.
 *
 * Not production code: the flag is baked into byte 13 of every record (docs/45) and nothing on the
 * ranking path decodes a name. Putting this in `main` would invite a caller, and a fifth
 * implementation of the suffix rules on the ranking path is exactly what the flag exists to
 * prevent. The fixture needs it because it is the *builder*, and the builder is the side that
 * decides the bit.
 */
fun looksLikeStation(name: String): Boolean {
    var end = name.length
    while (end > 0 && name[end - 1] == ')') end--
    val n = name.substring(0, end).trim()
    return n.endsWith("Hbf") ||
        n.endsWith("Hauptbahnhof") ||
        n.endsWith("Bahnhof") ||
        n.endsWith(" Bf") ||
        n.contains(" Hbf")
}

/**
 * `kSampleStations` from vst_fixture.dart, copied verbatim — the same five stations, the same
 * ranks, the same coordinates.
 *
 * NOT the Rust's `five()` (extract.rs:242-250), which looks similar and is not: different ranks
 * (3,1,1,1,2 against 3,2,2,1,1) and different coordinates for Wangen and for Neustadt-20. The CRC
 * in [StationExtractTest] is a number taken from a Dart run, and only the Dart set produces it.
 */
val SAMPLE_STATIONS = listOf(
    VstStation(3, "Köln Hbf", 50.9430, 6.9586, 3),
    VstStation(11, "Kißlegg Bahnhof", 47.7914, 9.8921, 2),
    VstStation(12, "Wangen im Allgäu", 47.6874, 9.8255, 2),
    VstStation(20, "Neustadt", 53.1000, 10.8000, 1),
    VstStation(21, "Neustadt", 49.3500, 8.1400, 1),
)

/**
 * `plausibleTable` from vst_fixture.dart: a table big enough to pass
 * [VstFormat.MIN_PLAUSIBLE_COUNT], scattered over Germany with a fixed sequence so two runs
 * produce the same file.
 */
fun plausibleTable(count: Int = 1200, startId: Int = 1): List<VstStation> {
    var seed = 0x2F6E2B1L
    fun next(): Double {
        seed = (seed * 1103515245L + 12345L) and 0x7FFFFFFFL
        return seed.toDouble() / 0x7FFFFFFF.toDouble()
    }
    return (0 until count).map { i ->
        VstStation(
            startId + i,
            if (i % 2 == 0) "Musterstadt $i Hbf" else "Musterstadt $i, Markt",
            47.3 + next() * 7.6,
            5.9 + next() * 9.1,
            (i % 3) + 1,
        )
    }
}
