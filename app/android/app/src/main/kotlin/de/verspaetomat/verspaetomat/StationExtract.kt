package de.verspaetomat.verspaetomat

import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import java.util.Arrays
import java.util.zip.CRC32
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The station table as the phone holds it, read in the background (issue #40).
 *
 * The byte layout is the contract with `backend/src/stations/extract.rs`, written out field by
 * field in docs/45 and again below. Three other implementations read the same bytes — Rust on the
 * laptop, Dart in the app (`app/lib/stations/station_extract.dart`), Swift in the iOS background
 * layer — and the answer this file computes has to be the answer all three compute, station for
 * station and in the same order. `app/android/app/src/test/.../StationParityTest.kt` is where that
 * is asserted rather than assumed.
 *
 * Nothing here imports `android.*` except [LocalStations.file], which is the one function that
 * needs a `Context`. That is deliberate: the hot path takes a [File], so the whole reader and the
 * whole scan run under plain JVM unit tests with no Robolectric and no device. If something in
 * here ever needs the Android framework to parse bytes, the seam is in the wrong place.
 */
object VstFormat {
    /** `"VSST"` — `extract::MAGIC` (backend/src/stations/extract.rs:23). */
    internal val MAGIC = byteArrayOf(0x56, 0x53, 0x53, 0x54)

    /** Copy, so nothing can scribble on the constant it was compared against. */
    fun magic(): ByteArray = MAGIC.copyOf()

    /** `extract::FORMAT` (extract.rs:25). Anything else: keep the extract already in hand. */
    const val SUPPORTED_FORMAT = 1

    /** `extract::HEADER_LEN` (extract.rs:26). A longer header is fine and is skipped over. */
    const val MIN_HEADER_LEN = 32

    /** `extract::RECORD_LEN` (extract.rs:27). A longer record is fine and is strided over. */
    const val MIN_RECORD_LEN = 20

    /** Record byte 13, bit 0: `looks_like_station` of the name, baked in (extract.rs:31). */
    const val FLAG_LOOKS_LIKE_STATION = 1

    /** `stations::NEARBY_MAX_M` (backend/src/stations/mod.rs:42). */
    const val NEARBY_MAX_M = 50_000.0

    /** `train::transitous::RANK_BAND_M` (backend/src/train/transitous.rs:26). */
    const val RANK_BAND_M = 300

    /** `StationStore.minPlausibleCount` (app/lib/stations/station_store.dart:74), on this side. */
    const val MIN_PLAUSIBLE_COUNT = 1_000

    /**
     * The most stations this reader can rank, because [StationExtract.nearby] packs
     * `(distance, record index)` into one `Long` and gives the index twenty bits. A table this
     * large would be a 21 MB file; refusing it whole is the format's own rule for anything that
     * does not read (docs/45, „Was ein Leser prüft").
     */
    const val MAX_RANKABLE_COUNT = 1 shl 20
}

/** Every way a file can be plausible and wrong. There is no partial read. */
class VstFormatException(message: String) : Exception(message)

/** One station in a nearby answer. [id] is the wire form `"vs:4711"` (stations/mod.rs:57). */
data class NearbyStation(
    val id: String,
    val name: String,
    val lat: Double,
    val lon: Double,
    val distanceM: Int,
    val rank: Int,
    /** The record index this came from. The tiebreak both sorts need; see [NearbyAnswer.nearestFirst]. */
    internal val at: Int,
)

/**
 * What `GET /v1/stations/nearby` used to answer, computed from the file.
 *
 * [stations] is in the server's ranked order (handlers.rs:87, `Index::nearby`,
 * backend/src/stations/mod.rs:225-231). The other two fields are the answer's own scope, and they
 * are not decoration: `GeofenceRules.umbrellaRadius` (app/ios/Runner/Geofence.swift:92-123) sizes
 * the umbrella from the first station it did *not* register and fails closed on [complete].
 * Issue #31 is the record of what a wrong one costs.
 */
data class NearbyAnswer(
    val stations: List<NearbyStation>,
    /** How far this answer reaches: the distance of the farthest station in it, 0 when empty. */
    val searchRadiusM: Int,
    /** False only when there is genuinely nothing within fifty kilometres (mod.rs:228). */
    val complete: Boolean,
) {
    // Deliberate, and the reason belongs here rather than in a commit message: issue #40 gives
    // Android these two numbers for the first time — `fetchNearby` parsed only the station array —
    // and then **does not use them to resize the umbrella**. Android keeps its flat 8 km where iOS
    // computes 1 to 200 km from `searchRadiusM` and `complete`.
    //
    // That is not an oversight. #40 changes where the answer comes from; sizing the umbrella from
    // it is a different change, and sizing is the ground issue #31 was fought on: a radius
    // computed in one town and recentred on the next never fires again, and the stale set never
    // refreshes — strictly worse than a cautious circle that always fires. One change at a time,
    // with the kill switch guarding this one. Whoever closes that gap needs a staleness guard in
    // the same commit, and `app/lib/content/legal.dart` needs rewriting first, because it tells
    // the passenger the Android circle is always eight kilometres.


    /**
     * Distance ascending, ties by record index — the order region selection wants
     * (Geofence.swift:282 re-sorts the ranked answer the same way).
     *
     * The index tiebreak is not cosmetic. The region set cuts this list at
     * `GeofenceManager.MAX_REGIONS` away from home and at `NEAREST_NEAR_HOME` at home, so a tie
     * that straddles the cut decides which of two stations gets a region, not merely their order.
     */
    fun nearestFirst(): List<NearbyStation> = stations.sortedWith(compareBy({ it.distanceM }, { it.at }))
}

/** Great-circle distance, the one formula all four implementations share. */
object Haversine {
    private const val R = 6_371_000.0
    private const val DEG = PI / 180.0

    /**
     * `train::haversine_m` (backend/src/train/mod.rs:393), `haversineM`
     * (app/lib/stations/station_rules.dart:44-54), `haversine` (extract.rs:376-383).
     *
     * `kotlin.math`, which is `java.lang.Math`, never `java.lang.StrictMath`: the other three use
     * their platform libm too, and a slower-but-differently-rounded one would not help.
     */
    fun metres(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val p1 = lat1 * DEG
        val p2 = lat2 * DEG
        val dp = (lat2 - lat1) * DEG
        val dl = (lon2 - lon1) * DEG
        val sdp = sin(dp / 2.0)
        val sdl = sin(dl / 2.0)
        val a = sdp * sdp + cos(p1) * cos(p2) * sdl * sdl
        return 2.0 * R * atan2(sqrt(a), sqrt(1.0 - a))
    }
}

/**
 * The order the ranked half of a nearby answer is sorted in.
 *
 * An interface only so the parity suite can run the whole comparison again through a deliberately
 * broken order and prove the comparison notices. Production has exactly one implementation,
 * [NearbyOrders.SERVER]; nothing outside the tests may pass another.
 */
fun interface NearbyOrder {
    /**
     * The sort key of one kept entry, compared element by element — `nearby_order`'s tuple
     * (backend/src/train/transitous.rs:492-494) with the record index appended
     * (station_index.dart:70).
     */
    fun key(x: StationExtract, distanceM: Int, at: Int): IntArray
}

object NearbyOrders {
    /**
     * `(distance / 300, -rank, named ? 0 : 1, distance, record index)`.
     *
     * The distance is the **rounded** metres: the Rust divides the rounded `i64`, so rounding
     * after the division would put a station in the wrong band (station_rules.dart:150-152).
     */
    val SERVER = NearbyOrder { x, d, i ->
        intArrayOf(
            d / VstFormat.RANK_BAND_M,
            -x.rank(i),
            if (x.namedLikeStation(i)) 0 else 1,
            d,
            i,
        )
    }

    /** Lexicographic over the key, which is how a tuple compares in Rust and in Dart. */
    internal fun comparator(x: StationExtract, order: NearbyOrder): Comparator<Long> =
        Comparator { a, b ->
            val ka = order.key(x, hitDistance(a), hitAt(a))
            val kb = order.key(x, hitDistance(b), hitAt(b))
            var c = 0
            var i = 0
            while (c == 0 && i < ka.size && i < kb.size) {
                c = ka[i].compareTo(kb[i])
                i++
            }
            c
        }
}

/**
 * One hit of the scan: rounded metres in the high bits, record index in the low twenty.
 *
 * The distance is at most 50,000 (16 bits) and the index below 2^20
 * ([VstFormat.MAX_RANKABLE_COUNT]), both non-negative — so ascending numeric order over the packed
 * value IS (distance ascending, index ascending), which is what the Rust's stable sort by distance
 * leaves behind over a table in ascending id order. No comparator, and no stability question.
 */
private const val HIT_INDEX_BITS = 20
private const val HIT_INDEX_MASK = (1L shl HIT_INDEX_BITS) - 1L

private fun packHit(distanceM: Int, at: Int): Long = (distanceM.toLong() shl HIT_INDEX_BITS) or at.toLong()

private fun hitDistance(hit: Long): Int = (hit ushr HIT_INDEX_BITS).toInt()

private fun hitAt(hit: Long): Int = (hit and HIT_INDEX_MASK).toInt()

/**
 * A parsed `.vst`, held as the raw bytes plus a little-endian view of them.
 *
 * Nothing is unpacked at load: the records stay where they are and every accessor is an absolute
 * read at a computed offset. That is what lets a background wake read 280 KB, scan it and allocate
 * nothing but the answer.
 */
class StationExtract private constructor(
    private val raw: ByteArray,
    private val buf: ByteBuffer,
    /** The header's `format`. */
    val format: Int,
    /** The header's `header_len` and `record_len`, as read — never assumed to be 32 and 20. */
    val headerLen: Int,
    val recordLen: Int,
    val count: Int,
    val blobLen: Int,
    private val blobAt: Int,
    /** The header's `version`: the `station_imports` row this extract was cut from. */
    val tableVersion: Long,
    /** The header's `generated`, unix seconds UTC. */
    val generatedAt: Long,
    /** The header's `crc32`, as read and as verified over `raw[headerLen..]`. */
    val crc32: Long,
    val byteLength: Int,
) {
    private fun at(i: Int): Int = headerLen + i * recordLen

    /** The table's own id, the `4711` of `vs:4711`. */
    fun id(i: Int): Long = buf.getInt(at(i)).toLong() and 0xFFFF_FFFFL

    fun lat(i: Int): Double = buf.getInt(at(i) + 4) / 1_000_000.0

    fun lon(i: Int): Double = buf.getInt(at(i) + 8) / 1_000_000.0

    /** The docs/23 ladder: 3 long distance, 2 regional, 1 S-Bahn only. */
    fun rank(i: Int): Int = buf.get(at(i) + 12).toInt() and 0xFF

    fun flags(i: Int): Int = buf.get(at(i) + 13).toInt() and 0xFF

    /**
     * `looks_like_station` of this station's name, decided at build time.
     *
     * Read out of the flags byte and never re-derived from the name: that is the whole reason the
     * bit exists (docs/45, „Warum nicht einfach JSON", point 2), and re-deriving it would put a
     * fifth implementation of the suffix rules on the ranking path.
     */
    fun namedLikeStation(i: Int): Boolean = flags(i) and VstFormat.FLAG_LOOKS_LIKE_STATION != 0

    /**
     * The display name, decoded from the blob on demand. Nothing on the ranking path calls this
     * until the answer is being built, so a scan that finds nothing never touches the blob.
     *
     * Deliberate: `java.lang.String` substitutes U+FFFD for malformed UTF-8 where Rust's
     * `from_utf8` and Dart's `utf8.decode` both throw. The CRC makes that unreachable for a file
     * that got this far, and the parity fixture compares ids rather than names — so this is a
     * decision, not an accident of the Java API.
     */
    fun name(i: Int): String {
        val off = (buf.getInt(at(i) + 16).toLong() and 0xFFFF_FFFFL).toInt()
        val len = buf.get(at(i) + 14).toInt() and 0xFF
        return String(raw, blobAt + off, len, StandardCharsets.UTF_8)
    }

    /**
     * The nearest stations, ranked the way the server ranks them — `Index::nearby`
     * (backend/src/stations/mod.rs:205-232) and `StationIndex.nearby`
     * (app/lib/stations/station_index.dart:41-88), whose reference form is `nearby_over`
     * (extract.rs:389-404).
     *
     * **On [limit], and why Android now asks for twenty-five.** While this was an HTTP call,
     * `fetchNearby` sent no `limit` and landed on the server's default of three
     * (handlers.rs:80) where iOS asked for twenty-five (`GeofenceRules.nearbyLimit`,
     * Geofence.swift:131). Reading locally removes the reason for the difference: the scan is one
     * pass over every record whatever the limit is, and `limit` only decides `min(n, limit)`, a
     * sort over at most that many entries and that many names decoded out of the blob. Measured
     * on a laptop JVM over the live 7,604-station table, a whole answer costs about 0.2 ms and
     * three costs the same as twenty-five. Keeping three would have preserved a platform
     * difference for no reason, and an unexplained platform difference is how „ein Kreis von
     * 8 km" ended up in the Datenschutzerklärung as though it were true of both phones.
     *
     * It is not free in behaviour, and the cost is paid next door: a list this deep reaches a
     * station's own Haltestelle under a second feed's id, so the region set must dedupe with
     * [StationNames.samePlace] and not by id. See that object for what happens otherwise.
     */
    fun nearby(lat: Double, lon: Double, limit: Int): NearbyAnswer = nearby(lat, lon, limit, NearbyOrders.SERVER)

    internal fun nearby(lat: Double, lon: Double, limit: Int, order: NearbyOrder): NearbyAnswer {
        // One pass over every record, nothing boxed. 1024 slots to begin with: measured over the
        // live extract the largest fifty-kilometre neighbourhood is 351 stations, near
        // 51.3124, 7.0897 (Hagen/Wuppertal), so this is about three times today's worst case and
        // doubles rather than failing if the table ever outgrows it.
        //
        // No bounding-box pre-filter: one loop shape in four languages, and 7,604 haversines
        // measure at 1.9 ms cold in Dart (station_index.dart:8-9).
        var hits = LongArray(1024)
        var n = 0
        for (i in 0 until count) {
            val d = Haversine.metres(lat, lon, lat(i), lon(i))
            // The **unrounded** distance decides the cut-off, as it does in all three others.
            if (d > VstFormat.NEARBY_MAX_M) continue
            // `java.lang.Math.round` written out in full, and NOT `kotlin.math.round`, which is
            // `Math.rint` and rounds ties to even. Ties-up is what Rust's `f64::round` and Dart's
            // `double.round()` do for d >= 0, and a half-metre disagreement here moves a station
            // across a 300 m band edge.
            val dRounded = java.lang.Math.round(d).toInt()
            if (n == hits.size) hits = hits.copyOf(hits.size * 2)
            hits[n++] = packHit(dRounded, i)
        }
        Arrays.sort(hits, 0, n)

        val kept = min(n, limit)
        // After the cut and before the re-sort: how far this answer actually reaches
        // (station_index.dart:55-57, mod.rs:216). Nearest first for the cut, best-ranked first for
        // the answer — truncating after the rank sort could drop a nearer station in favour of a
        // better one further out, and then the first station the phone did not register is no
        // longer the nearest one it did not register.
        val searchRadiusM = if (kept == 0) 0 else hitDistance(hits[kept - 1])

        // The second sort, over the kept entries only — at most `limit` of them, so the boxing
        // here is twenty-five Longs and not 7,604.
        val ranked = ArrayList<Long>(kept)
        for (k in 0 until kept) ranked.add(hits[k])
        ranked.sortWith(NearbyOrders.comparator(this, order))

        return NearbyAnswer(
            stations = ranked.map { hit ->
                val i = hitAt(hit)
                NearbyStation(
                    id = "vs:" + id(i),
                    name = name(i),
                    lat = lat(i),
                    lon = lon(i),
                    distanceM = hitDistance(hit),
                    rank = rank(i),
                    at = i,
                )
            },
            searchRadiusM = searchRadiusM,
            complete = kept > 0,
        )
    }

    companion object {
        /**
         * docs/45's list, in docs/45's order, every failure a [VstFormatException].
         *
         * No gzip sniff. Dart has one (station_extract.dart:184-194) because it reads HTTP bodies
         * and Caddy serves a `.vst.gz` sibling; the file on disk is always raw
         * (station_store.dart:231-233 writes the decoded bytes). A gzipped file here would be a
         * Dart bug, and refusing it says so.
         */
        @Throws(VstFormatException::class)
        fun decode(raw: ByteArray): StationExtract {
            if (raw.size < VstFormat.MIN_HEADER_LEN) {
                throw VstFormatException("${raw.size} bytes is shorter than the header")
            }
            val buf = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
            for (i in VstFormat.MAGIC.indices) {
                if (raw[i] != VstFormat.MAGIC[i]) {
                    throw VstFormatException("not a station extract: the magic is ${raw.take(4)}")
                }
            }
            // Every u16/u32 is widened before it is checked, so a hostile file cannot arrive
            // negative and slip past a bound.
            val format = buf.getShort(4).toInt() and 0xFFFF
            if (format != VstFormat.SUPPORTED_FORMAT) {
                throw VstFormatException("extract format $format, this reader knows ${VstFormat.SUPPORTED_FORMAT}")
            }
            val headerLen = buf.getShort(6).toInt() and 0xFFFF
            if (headerLen < VstFormat.MIN_HEADER_LEN) {
                throw VstFormatException("header_len $headerLen is shorter than ${VstFormat.MIN_HEADER_LEN}")
            }
            val countL = buf.getInt(8).toLong() and 0xFFFF_FFFFL
            if (countL < 1) throw VstFormatException("an extract of nothing")
            val recordLenL = buf.getInt(12).toLong() and 0xFFFF_FFFFL
            if (recordLenL < VstFormat.MIN_RECORD_LEN) {
                throw VstFormatException("record_len $recordLenL is shorter than ${VstFormat.MIN_RECORD_LEN}")
            }
            val blobLenL = buf.getInt(16).toLong() and 0xFFFF_FFFFL
            val generated = buf.getInt(20).toLong() and 0xFFFF_FFFFL
            val tableVersion = buf.getInt(24).toLong() and 0xFFFF_FFFFL
            val crc = buf.getInt(28).toLong() and 0xFFFF_FFFFL

            // A cheap bound before the arithmetic, so the product cannot approach Long overflow.
            if (recordLenL > raw.size || countL > raw.size) {
                throw VstFormatException("the file says more bytes than it has")
            }
            val want = headerLen.toLong() + recordLenL * countL + blobLenL
            if (want != raw.size.toLong()) {
                throw VstFormatException("the file says $want bytes and is ${raw.size}")
            }
            if (countL > VstFormat.MAX_RANKABLE_COUNT) {
                throw VstFormatException("$countL stations is more than this reader can rank")
            }

            // Over `[headerLen, EOF)`, never over a literal 32: a grown header keeps `format` at 1
            // and a reader that hardcodes the offset breaks on the first field anybody adds
            // (docs/45, „Was ein Leser prüft" step 8).
            val actual = CRC32().apply { update(raw, headerLen, raw.size - headerLen) }.value
            if (actual != crc) {
                throw VstFormatException("the checksum does not match: the file is damaged")
            }

            val count = countL.toInt()
            val recordLen = recordLenL.toInt()
            val blobAt = headerLen + recordLen * count
            // One validating pass. The names are NOT decoded — a nearby answer decodes at most
            // twenty-five of them, and a launch that only wants to know the file is sound should
            // not pay for 7,604 strings.
            for (i in 0 until count) {
                val at = headerLen + i * recordLen
                val nameLen = buf.get(at + 14).toInt() and 0xFF
                if (nameLen < 1) throw VstFormatException("record $i has no name")
                val nameOff = buf.getInt(at + 16).toLong() and 0xFFFF_FFFFL
                if (nameOff + nameLen > blobLenL) {
                    throw VstFormatException("record $i names bytes outside the blob")
                }
                // Byte 15 is `reserved`. It is ignored rather than checked for zero, because that
                // is where the next field goes and a reader that asserts it is 0 refuses the first
                // grown file (docs/45:67,153).
                //
                // Ascending ids are not checked here either: the format guarantees the order
                // (docs/45, „Die Datensätze sind streng aufsteigend nach id sortiert") and the
                // ranking needs only the index. The parity suite asserts it over the real file.
            }
            return StationExtract(
                raw = raw,
                buf = buf,
                format = format,
                headerLen = headerLen,
                recordLen = recordLen,
                count = count,
                blobLen = blobLenL.toInt(),
                blobAt = blobAt,
                tableVersion = tableVersion,
                generatedAt = generated,
                crc32 = crc,
                byteLength = raw.size,
            )
        }

        /** Reads the file and decodes it. An [IOException] becomes a [VstFormatException]. */
        @Throws(VstFormatException::class)
        fun open(file: File): StationExtract {
            val raw = try {
                file.readBytes()
            } catch (e: IOException) {
                throw VstFormatException("${file.name} could not be read: ${e.message}")
            }
            return decode(raw)
        }
    }
}

/**
 * The seam the geofence layer calls: a file path in, a nearby answer out, nothing on the network.
 *
 * This is the only place in this file that may name `android.*`.
 */
object LocalStations {
    /**
     * `<filesDir>/stations/stations.vst` — the same file Dart writes, because
     * `getApplicationSupportDirectory()` is `getFilesDir()` on Android
     * (app/lib/stations/station_store.dart:49,59,297-301,310-313).
     *
     * `filesDir` is credential-encrypted storage, and that is fine here: `BootReceiver`
     * (AndroidManifest.xml) is not `directBootAware` and only listens for `BOOT_COMPLETED`, which
     * is delivered after the first unlock; Play-services geofences do not survive a reboot, so
     * `BootReceiver.reregister` is the only thing that can put a fence back, and by then this
     * storage is open for the rest of the boot session. The between-boot-and-unlock case iOS has
     * to decide cannot arise.
     */
    fun file(ctx: android.content.Context): File = File(ctx.filesDir, "stations/stations.vst")

    /**
     * The nearby answer, from the file.
     *
     * `null` means the file could not be read — missing, damaged, truncated, the wrong format, or
     * too small to be the real table. A non-null answer with **no stations** means there is
     * genuinely nothing within fifty kilometres. They are different things and the caller must
     * treat them differently: a failed lookup is transient and the old set is still the best
     * guess, while an empty answer says the old set describes somewhere else and keeping it
     * registered is worse than dropping it. That is the whole of issue #31
     * (Geofence.swift:1155-1164).
     *
     * Checked, so it is a decision and not an accident: Android **already** draws this line.
     * `onUmbrellaExit` (GeofenceManager.kt:277-280) writes `prefs("nearest")` only when
     * `fetchNearby` returned non-null, so a failure keeps the stored list and an empty answer
     * replaces it with an empty one. Returning `null` here therefore lands on the same branch the
     * network path landed on, and the caller needs no change to keep that behaviour.
     *
     * What Android does not have, and gains here, is [NearbyAnswer.complete] and
     * [NearbyAnswer.searchRadiusM]: `fetchNearby` parsed only the station array, so the phone
     * could never tell „nothing is near" from „the answer was truncated" — which is exactly what
     * `GeofenceRules.umbrellaRadius` fails closed on.
     */
    fun nearby(file: File, lat: Double, lon: Double, limit: Int): NearbyAnswer? =
        nearby(file, lat, lon, limit) { android.util.Log.w("Geofence", it) }

    /**
     * The same, with somewhere to put the warning.
     *
     * The logger is a parameter so the tests can reach this without `android.util.Log` — which,
     * with `returnDefaultValues` deliberately unset, throws „not mocked" on the JVM. That is the
     * point: the throwing stub is what keeps `android.*` out of the reader, so the one call that
     * does need it is handed in from outside rather than smuggled in here.
     */
    internal fun nearby(
        file: File,
        lat: Double,
        lon: Double,
        limit: Int,
        warn: (String) -> Unit,
    ): NearbyAnswer? = try {
        val x = StationExtract.open(file)
        if (x.count < VstFormat.MIN_PLAUSIBLE_COUNT) {
            // A truncated-but-structurally-valid extract is not an extract: the table has held
            // over 7,000 stations since #37, so anything this small is a mistake upstream and not
            // a smaller Germany (station_store.dart:70-74).
            warn("stations.vst holds only ${x.count} stations")
            null
        } else {
            x.nearby(lat, lon, limit)
        }
    } catch (e: VstFormatException) {
        warn("stations.vst unusable: ${e.message}")
        null
    }
}

/**
 * One platform under two names — `GeofenceRules.samePlace` and `GeofenceRules.normalise`
 * (app/ios/Runner/Geofence.swift:208-213 and :215-241), ported so Android can dedupe its region
 * set the way iOS does.
 *
 * **Why this had to come with the wider nearby list.** Android deduped by id alone
 * (`GeofenceManager.kt:194-195`), which was survivable while the server handed it three stations:
 * a three-deep list rarely contains one station twice. Asking for twenty-five changes that. The
 * list now reaches deep enough to hold a station's own Haltestelle under a second feed's id, both
 * get a circle, the phone sits inside both, and Wangen is nudged twice — issue #11, which docs/30
 * was supposed to have ended. Ids do not catch it; the name and 250 m do.
 *
 * It lives here rather than beside the caller because it is pure — two names and two coordinates
 * in, a boolean out — and this is the file the unit tests can reach without a device. That is the
 * same reason the scan is here.
 */
object StationNames {
    /**
     * Two entries this close with the same normalised name are one platform listed twice
     * (Geofence.swift:210). The same number as the Swift, and far tighter than the 1 km
     * `stations::SAME_STATION_M` the importer folds with — that one decides whether two rows are
     * one station, this one decides whether two circles are one circle.
     */
    const val SAME_PLACE_M = 250.0

    /**
     * Stripped from the end, first match wins, and **the order is load-bearing**: `hbf` before
     * `bf`, or „kolnhbf" loses two characters instead of three and „Köln Hbf" stops matching
     * „Köln Hauptbahnhof". Swift's list, in Swift's order (Geofence.swift:237).
     */
    private val STATION_WORDS = listOf("bahnhof", "hbf", "bf")

    /** Combining marks, which is what diacritic folding removes once NFD has separated them. */
    private val COMBINING_MARKS = Regex("\\p{Mn}+")

    /**
     * The fold that decides whether two names are the same place.
     *
     * Step for step from Geofence.swift:215-241, and every step earns itself:
     *  1. lowercase — locale-independent on both sides, so a Turkish phone folds „I" our way.
     *  2. `hauptbahnhof` → `hbf`, so „Köln Hauptbahnhof" and „Köln Hbf" are one place.
     *  3. **`ß` → `ss`, and it must happen before the diacritic folding.** `ß` is a letter, not an
     *     accent, so folding leaves it alone — and the feeds disagree about it: DELFI writes
     *     „Kißlegg", the Swiss feed writes „Kisslegg". Without this they are two places, which is
     *     two circles on one platform and the exact bug this is being ported to prevent.
     *  4. diacritic folding: NFD, then drop the combining marks. Java's equivalent of Swift's
     *     `.folding(options: .diacriticInsensitive)`.
     *  5. keep letters and digits, so punctuation and spacing cannot make two feeds disagree —
     *     „Wangen (Allgäu)" and „Wangen Allgaeu" are not our problem, but „Wangen(Allgäu)" is.
     *  6. drop one trailing word for the thing itself, so „… Bahnhof" and „…" are one place.
     *     Only when something is left: „Bahnhof" alone normalises to „bahnhof" and not to "".
     *
     * Not to be confused with `serverStationFold` (app/lib/stations/station_rules.dart:97), which
     * is `train::normalise_station_name` and belongs to the **search**; or with `normaliseStation`
     * (ride_widgets.dart:122), the display-side fold behind `sameStation`. Three folds, three
     * jobs. This one is the region set's.
     */
    fun normalise(name: String): String {
        var s = name.lowercase()
            .replace("hauptbahnhof", "hbf")
            .replace("ß", "ss")
        s = COMBINING_MARKS.replace(java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD), "")
        s = s.filter { it.isLetterOrDigit() }
        for (suffix in STATION_WORDS) {
            if (s.endsWith(suffix) && s.length > suffix.length) {
                s = s.dropLast(suffix.length)
                break
            }
        }
        return s
    }

    /**
     * Close together, and one normalised name is the other or a prefix of it.
     *
     * The distance is [Haversine.metres] rather than `Location.distanceBetween`, which is what the
     * rest of `GeofenceManager` uses. Two reasons, and the first is the one that decides it:
     * `Location` is an `android.*` class that throws „not mocked" under a plain JVM unit test, so
     * using it here would put this rule back out of reach of the tests it exists to have. The
     * second is that it is the same haversine the scan just used to produce these stations, so the
     * two agree by construction. iOS uses CLLocation's WGS84 geodesic, which differs from a
     * sphere by a few tenths of a percent — under a metre at 250 m, and it can only change the
     * answer for a pair sitting within that metre of the boundary.
     */
    fun samePlace(
        aName: String,
        aLat: Double,
        aLon: Double,
        bName: String,
        bLat: Double,
        bLon: Double,
    ): Boolean {
        if (Haversine.metres(aLat, aLon, bLat, bLon) > SAME_PLACE_M) return false
        val x = normalise(aName)
        val y = normalise(bName)
        // An empty fold matches everything by prefix, so it must match nothing instead.
        if (x.isEmpty() || y.isEmpty()) return false
        return x == y || x.startsWith(y) || y.startsWith(x)
    }

    /** The same, for the two stations a region set is choosing between. */
    fun samePlace(a: Station, b: Station): Boolean =
        samePlace(a.name, a.lat, a.lon, b.name, b.lat, b.lon)
}
