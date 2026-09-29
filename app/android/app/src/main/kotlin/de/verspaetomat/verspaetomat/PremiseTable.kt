package de.verspaetomat.verspaetomat

import android.content.Context
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.CRC32

/** One circle of a premise: the ring or a touch point. */
data class PremiseCircle(val lat: Double, val lon: Double, val radius: Double)

/** What the native layer needs of a premise (issue #64, docs/48). */
data class PremiseEntry(val ring: PremiseCircle, val touch: List<PremiseCircle>)

/**
 * The sibling of [LocalStations] for the station premises Dart downloads
 * (`premise_store.dart`) into `<filesDir>/stations/umrisse.bin`. Never written here.
 *
 * The reader mirrors `backend/src/stations/outlines.rs` (`parse_file`), `premise_file.dart` and
 * `PremiseTable` in `GeofenceStations.swift` check for check; all four read
 * `app/test/fixtures/umrisse-fixture.bin` to the same numbers. Derived from OpenStreetMap, ODbL.
 */
class PremiseTable(val version: Long, val generated: Long, val entries: Map<Long, PremiseEntry>) {
    val count: Int get() = entries.size

    /** Our station id is `vs:<n>`; an older build's MOTIS id has no premise. */
    fun entry(stationId: String): PremiseEntry? =
        if (stationId.startsWith("vs:")) stationId.removePrefix("vs:").toLongOrNull()?.let { entries[it] } else null

    class Refused(why: String) : Exception(why)

    companion object {
        const val FILE = "stations/umrisse.bin"
        /** The same floor as Dart's `PremiseStore.minPlausibleCount`. */
        const val MIN_PLAUSIBLE = 1000
        private val MAGIC = byteArrayOf(0x56, 0x53, 0x4F, 0x4C) // "VSOL"

        fun parse(b: ByteArray): PremiseTable {
            if (b.size < 32) throw Refused("${b.size} bytes is no header")
            for (i in 0 until 4) if (b[i] != MAGIC[i]) throw Refused("not a VSOL file")
            val d = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
            fun u16(o: Int) = d.getShort(o).toInt() and 0xFFFF
            fun u32(o: Int) = d.getInt(o).toLong() and 0xFFFFFFFFL
            if (u16(4) != 1) throw Refused("format ${u16(4)}")
            val hl = u16(6)
            val count = u32(8)
            val rl = u32(12)
            val bl = u32(16)
            if (hl < 32 || rl < 20) throw Refused("header $hl, record $rl")
            if (hl + rl * count + bl != b.size.toLong()) throw Refused("length does not add up")
            val crc = CRC32().apply { update(b, hl, b.size - hl) }.value
            if (crc != u32(28)) throw Refused("crc32 does not match")
            val blob0 = hl + (rl * count).toInt()
            val out = HashMap<Long, PremiseEntry>(count.toInt())
            var last = 0L
            for (i in 0 until count.toInt()) {
                val o = hl + i * rl.toInt()
                val id = u32(o)
                if (id <= last) throw Refused("record $i out of order")
                last = id
                val nt = b[o + 14].toInt() and 0xFF
                val nc = b[o + 15].toInt() and 0xFF
                val off = u32(o + 16)
                if (off + nt * 10 + nc * 8 > bl) throw Refused("record $i points past the blob")
                val at = blob0 + off.toInt()
                val touch = (0 until nt).map { k ->
                    PremiseCircle(d.getInt(at + k * 10) / 1e6, d.getInt(at + k * 10 + 4) / 1e6, u16(at + k * 10 + 8).toDouble())
                }
                val ring = PremiseCircle(d.getInt(o + 4) / 1e6, d.getInt(o + 8) / 1e6, u16(o + 12).toDouble())
                // The server's `check_row`: a file that breaks it was not made by us.
                if (nc !in 3..24 || ring.radius !in 300.0..1000.0 || nt !in 1..6 || touch.any { it.radius < 120 }) {
                    throw Refused("record $i: shape")
                }
                out[id] = PremiseEntry(ring, touch)
            }
            return PremiseTable(u32(24), u32(20), out)
        }

        /** The file on disk, or null: none there, or not one we can trust. Nothing is deleted. */
        fun load(ctx: Context): PremiseTable? = try {
            val f = File(ctx.filesDir, FILE)
            if (!f.isFile) null else parse(f.readBytes()).takeIf { it.count >= MIN_PLAUSIBLE }
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * The fences with premises on (docs/48, Android). Android allows 100 geofences, so there is no
 * swapping and no state: every station of the set is registered for good — its touch points when
 * it has a premise, its 300 m ring when it has none — and entering one is the nudge. The ring
 * itself is not registered for a station with a premise: nothing on Android listens for it.
 */
object PremiseFences {
    const val TOUCH_PREFIX = "touch:"

    /** One fewer than Android's 100: the umbrella is the hundredth. `addGeofences` fails whole
     * above the limit, and then nothing at all is registered (docs/48, Umsetzungsregeln). */
    const val MAX_FENCES = 99

    data class Spec(val id: String, val stationId: String, val lat: Double, val lon: Double, val radius: Float)

    /** In the set's order, which is its importance; a station whose fences no longer fit is left
     * out whole, never half. */
    fun plan(stations: List<Station>, premise: (String) -> PremiseEntry?, stationRadius: Float): List<Spec> {
        val out = ArrayList<Spec>()
        for (s in stations) {
            val e = premise(s.id)
            val specs = if (e != null) {
                e.touch.mapIndexed { k, t -> Spec("$TOUCH_PREFIX${s.id}:${k + 1}", s.id, t.lat, t.lon, t.radius.toFloat()) }
            } else {
                listOf(Spec(GeofenceManager.STATION_PREFIX + s.id, s.id, s.lat, s.lon, stationRadius))
            }
            if (out.size + specs.size > MAX_FENCES) break
            out.addAll(specs)
        }
        return out
    }

    /** `touch:vs:17:2` → `vs:17`. Station ids may carry colons themselves; the number is last. */
    fun stationId(ofTouch: String): String? {
        if (!ofTouch.startsWith(TOUCH_PREFIX)) return null
        val rest = ofTouch.removePrefix(TOUCH_PREFIX)
        val colon = rest.lastIndexOf(':')
        return if (colon <= 0) null else rest.substring(0, colon)
    }
}
