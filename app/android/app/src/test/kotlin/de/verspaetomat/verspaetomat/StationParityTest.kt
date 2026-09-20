package de.verspaetomat.verspaetomat

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test

/**
 * One row of `testdata/stations/nearby-probes.tsv`: a position, a limit, and the answer
 * `Index::nearby` gives there.
 *
 * The columns are the fixture's own, as its header comment spells them out:
 * `lat lon limit n search_radius_m complete ids`. [ambiguous] is an eighth column the generator
 * may add for a row whose order flips under a one-ulp change of distance — a fact about four
 * libms rather than about any reader. Today's fixture carries none; this honours them if it
 * grows some, rather than the assertion being loosened instead.
 */
internal data class Probe(
    val lat: Double,
    val lon: Double,
    val limit: Int,
    val n: Int,
    val searchRadiusM: Int,
    val complete: Boolean,
    val ids: List<Long>,
    val ambiguous: Boolean,
)

/**
 * The four faulted runs go over every row, not a prefix.
 *
 * Measured: one full pass is about half a second, so the four cost roughly two seconds — the spec
 * budgeted 2-4 s for a single pass and was about four times pessimistic. The 200-row prefix it
 * offered as a fallback is not enough anyway: f1, f2 and f3 bite inside it, but f4 needs two
 * stations at the same rounded metre with the same rank and the same name flag, which the first
 * two hundred rows do not contain. A fault that goes unnoticed is the one thing this test exists
 * to prevent, so it gets the whole fixture.
 */
private const val FAULT_PROBES = Int.MAX_VALUE

/** What the columns are when the fixture does not name them — spec §5.1's order. */
private val DEFAULT_COLUMNS =
    listOf("lat", "lon", "limit", "search_radius_m", "complete", "ids", "label", "ambiguous")

/**
 * The acceptance: the answer this reader gives is the answer the table gives.
 *
 * Every other test in this source set runs against bytes this repository writes itself, which
 * proves the reader agrees with our reading of the format. This one reads the extract the backend
 * produced and a fixture of answers computed away from this code, and it is where a disagreement
 * between the Kotlin and the other three shows up.
 *
 * It asserts and never skips. The Swift half of this comparison has been failing since docs/30
 * precisely because nothing ran it; a suite that quietly opts out when its fixture is missing is
 * the same file with a different extension.
 */
class StationParityTest {

    @Test
    fun `it is the format this reader was written for`() {
        assertEquals(VstFormat.SUPPORTED_FORMAT, extract.format)
        assertTrue(extract.headerLen >= VstFormat.MIN_HEADER_LEN)
        assertTrue(extract.recordLen >= VstFormat.MIN_RECORD_LEN)
        assertTrue("a version-0 extract must never be published", extract.tableVersion > 0)
        assertTrue("generated ${extract.generatedAt} is before 2025", extract.generatedAt > 1_735_689_600L)
        assertTrue("the table has held over 7,000 stations since #37", extract.count > 7_000)
        assertTrue(extract.count >= VstFormat.MIN_PLAUSIBLE_COUNT)
    }

    @Test
    fun `the records ascend by id, which both sorts depend on`() {
        for (i in 1 until extract.count) {
            assertTrue(
                "record $i (id ${extract.id(i)}) does not follow ${extract.id(i - 1)}",
                extract.id(i) > extract.id(i - 1),
            )
        }
    }

    @Test
    fun `every station is on this planet, has a name, and carries no unknown flag`() {
        for (i in 0 until extract.count) {
            assertTrue(extract.lat(i) in -90.0..90.0)
            assertTrue(extract.lon(i) in -180.0..180.0)
            assertTrue(extract.name(i).isNotEmpty())
            assertTrue(extract.rank(i) in 0..3)
            // docs/45: bits 1-7 of the flags byte are 0.
            assertEquals(0, extract.flags(i) and VstFormat.FLAG_LOOKS_LIKE_STATION.inv() and 0xFF)
        }
    }

    @Test
    fun `the baked looks_like_station bit is a live tiebreak and not a constant`() {
        val named = (0 until extract.count).count { extract.namedLikeStation(it) }
        assertTrue("only $named of ${extract.count} carry the flag", named > 500)
        assertTrue("$named of ${extract.count} carry the flag", named < extract.count - 500)
    }

    @Test
    fun `the kotlin answer is the answer the table gave`() {
        val ms = System.currentTimeMillis()
        val bad = disagreements(NearbyOrders.SERVER, probes)
        println(
            "parity: ${probes.size} probes against ${extract.count} stations in " +
                "${System.currentTimeMillis() - ms} ms",
        )
        assertTrue(report("the server order", bad, probes.size), bad.isEmpty())
    }

    @Test
    fun `a broken scan is caught by the comparison`() {
        // Without this, the parity test proves only that two things agree — which a pair of broken
        // things also does. Each fault is one rule of `nearby_order`, removed or inverted; each
        // must produce disagreements, and the server order over the same rows must not.
        val ms = System.currentTimeMillis()
        val prefix = probes.take(FAULT_PROBES)
        val clean = disagreements(NearbyOrders.SERVER, prefix)
        assertTrue(report("the server order over the fault rows", clean, prefix.size), clean.isEmpty())
        val faults = listOf(
            "f1 band width 300 → 250" to NearbyOrder { x, d, i ->
                intArrayOf(d / 250, -x.rank(i), if (x.namedLikeStation(i)) 0 else 1, d, i)
            },
            "f2 the rank tiebreak inverted" to NearbyOrder { x, d, i ->
                intArrayOf(d / VstFormat.RANK_BAND_M, x.rank(i), if (x.namedLikeStation(i)) 0 else 1, d, i)
            },
            "f3 the name flag ignored" to NearbyOrder { x, d, i ->
                intArrayOf(d / VstFormat.RANK_BAND_M, -x.rank(i), 0, d, i)
            },
            "f4 the record-index tiebreak reversed" to NearbyOrder { x, d, i ->
                intArrayOf(d / VstFormat.RANK_BAND_M, -x.rank(i), if (x.namedLikeStation(i)) 0 else 1, d, -i)
            },
        )
        for ((what, order) in faults) {
            val bad = disagreements(order, prefix)
            // The count is printed, not only asserted, so it is written down the way the Rust's
            // own sweep writes its numbers down. A fault that starts biting in one row instead of
            // thirty is a change in the table worth noticing.
            println("fault $what: ${bad.size} of ${prefix.size} probes disagree")
            assertTrue("$what went unnoticed over ${prefix.size} probes", bad.isNotEmpty())
        }
        println("faults: ${faults.size} runs over ${prefix.size} probes in ${System.currentTimeMillis() - ms} ms")
    }

    // ---- the comparison ------------------------------------------------------------------------

    private fun disagreements(order: NearbyOrder, rows: List<Probe>): List<String> {
        val out = ArrayList<String>()
        for (p in rows) {
            // A row whose order flips under a one-ulp change of distance is a fact about four
            // libms, not about this reader. The generator marks those and all four suites skip
            // them — and print how many, so „none today" stays a measurement.
            if (p.ambiguous) continue
            val got = extract.nearby(p.lat, p.lon, p.limit, order)
            val gotIds = got.stations.map { it.id.removePrefix("vs:").toLong() }
            if (gotIds == p.ids &&
                gotIds.size == p.n &&
                got.searchRadiusM == p.searchRadiusM &&
                got.complete == p.complete
            ) {
                continue
            }
            out.add(facts(p, got, gotIds))
        }
        return out
    }

    /**
     * Everything that decides where a station lands in a nearby list, from both sides — the same
     * shape `Facts`/`classify` prints in extract.rs:433-520, so a Kotlin failure and a Rust
     * failure read the same and a human can tell a coordinate problem from a rank problem without
     * re-running anything.
     */
    private fun facts(p: Probe, got: NearbyAnswer, gotIds: List<Long>): String {
        val sb = StringBuilder()
        sb.append("at ${p.lat}, ${p.lon} limit ${p.limit}\n")
        sb.append("  want ids ${p.ids}\n")
        sb.append("  got  ids $gotIds\n")
        if (got.searchRadiusM != p.searchRadiusM) {
            sb.append("  search_radius_m: want ${p.searchRadiusM}, got ${got.searchRadiusM}\n")
        }
        if (got.complete != p.complete) {
            sb.append("  complete: want ${p.complete}, got ${got.complete}\n")
        }
        for (id in (p.ids + gotIds).distinct()) {
            val i = indexOfId(id)
            if (i < 0) {
                sb.append("  $id: not in this extract at all\n")
                continue
            }
            val d = java.lang.Math.round(Haversine.metres(p.lat, p.lon, extract.lat(i), extract.lon(i))).toInt()
            sb.append(
                "  $id ${extract.name(i)}: $d m, band ${d / VstFormat.RANK_BAND_M}, " +
                    "rank ${extract.rank(i)}, named ${extract.namedLikeStation(i)}, record $i\n",
            )
        }
        return sb.toString()
    }

    /** Binary search, which the format's ascending ids are there for (docs/45). */
    private fun indexOfId(id: Long): Int {
        var lo = 0
        var hi = extract.count - 1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            val v = extract.id(mid)
            when {
                v < id -> lo = mid + 1
                v > id -> hi = mid - 1
                else -> return mid
            }
        }
        return -1
    }

    private fun report(what: String, bad: List<String>, total: Int): String =
        "${bad.size} of $total probes disagree under $what\n\n" + bad.take(10).joinToString("\n")

    companion object {
        private lateinit var extract: StationExtract
        private lateinit var probes: List<Probe>

        @BeforeClass
        @JvmStatic
        fun load() {
            val file = Repo.extractFile
            val ms = System.currentTimeMillis()
            extract = StationExtract.open(file)
            println(
                "extract ${file.name}: ${extract.byteLength} bytes, format ${extract.format}, " +
                    "header_len ${extract.headerLen}, record_len ${extract.recordLen}, " +
                    "count ${extract.count}, blob_len ${extract.blobLen}, " +
                    "version ${extract.tableVersion}, generated ${extract.generatedAt}, " +
                    "crc32 0x${java.lang.Long.toHexString(extract.crc32)} — read and verified in " +
                    "${System.currentTimeMillis() - ms} ms",
            )
            probes = readProbes(Repo.probesFile, extract)
        }

        private fun readProbes(file: File, x: StationExtract): List<Probe> {
            if (!file.isFile) {
                throw AssertionError(
                    "no probe fixture at ${file.absolutePath}. Regenerate it with\n" +
                        "  cd backend && cargo test --release --lib write_the_nearby_probe_fixture " +
                        "-- --ignored --nocapture\n" +
                        "or point this run at one with -Dverspaetomat.probes=<path>.",
                )
            }
            var crc: Long? = null
            var count: Int? = null
            // The columns come out of the file's own header rather than being assumed, for the
            // same reason `header_len` does in the extract: four languages parse this fixture and
            // the generator is allowed to add a column at the end. A layout that cannot be read
            // fails by name below, not as a NumberFormatException forty rows in.
            var columns = DEFAULT_COLUMNS
            val out = ArrayList<Probe>()
            for (line in file.readLines()) {
                if (line.isEmpty()) continue
                if (line.startsWith("#")) {
                    // `# crc32=2957696257` (or `0x...`) and `# count=7604` — which extract these
                    // answers are about. A fixture for a different import is not a looser
                    // assertion, it is a wrong one, so a mismatch fails rather than skips.
                    Regex("crc32=(0x)?([0-9a-fA-F]+)").find(line)?.let {
                        crc = it.groupValues[2].toLong(if (it.groupValues[1].isEmpty()) 10 else 16)
                    }
                    Regex("count=(\\d+)").find(line)?.let { count = it.groupValues[1].toInt() }
                    val named = line.removePrefix("#").removePrefix(" columns:").trim()
                        .split(Regex("[\t ]+")).map { it.trim('[', ']') }
                    if (named.size >= 3 && named[0] == "lat" && named[1] == "lon") columns = named
                    continue
                }
                val f = line.split("\t")
                fun at(name: String): String? = columns.indexOf(name).let { if (it in f.indices) f[it] else null }
                require(f.size >= 6) { "malformed probe row: $line" }
                val idField = at("ids") ?: error("the fixture names no `ids` column: $columns")
                val ids = if (idField.isEmpty()) emptyList() else idField.split(",").map { it.toLong() }
                // `n` is a redundant column in some revisions of the fixture; when it is there it
                // has to agree with the ids beside it.
                at("n")?.let { require(it.toInt() == ids.size) { "row says n=$it, lists ${ids.size} ids: $line" } }
                out.add(
                    Probe(
                        lat = (at("lat") ?: error("no `lat`")).toDouble(),
                        lon = (at("lon") ?: error("no `lon`")).toDouble(),
                        limit = (at("limit") ?: error("no `limit`")).toInt(),
                        n = ids.size,
                        searchRadiusM = (at("search_radius_m") ?: error("no `search_radius_m`")).toInt(),
                        // 1/0 or true/false: both spellings have been in this file.
                        complete = (at("complete") ?: error("no `complete`")).let { it == "1" || it == "true" },
                        ids = ids,
                        ambiguous = at("ambiguous") == "ambiguous",
                    ),
                )
            }
            val belongs = "the probe fixture is not about this extract — regenerate it with " +
                "`cargo test --release --lib write_the_nearby_probe_fixture -- --ignored`"
            assertTrue("$belongs (it names no crc32)", crc != null)
            assertTrue("$belongs (it names no count)", count != null)
            assertEquals(belongs, x.crc32, crc!!)
            assertEquals(belongs, x.count.toLong(), count!!.toLong())
            assertTrue("the probe fixture is empty", out.isNotEmpty())
            println(
                "probes ${file.absolutePath}: ${out.size} rows, " +
                    "${out.count { it.ambiguous }} ambiguous, limits ${out.map { it.limit }.distinct().sorted()}",
            )
            return out
        }
    }
}
