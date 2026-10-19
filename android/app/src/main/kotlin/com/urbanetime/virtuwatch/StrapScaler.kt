package com.urbanetime.virtuwatch

import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Makes the STRAP of a watch bigger than its case.
 *
 * The models are single meshes (strap and case fused, no separate nodes), so the strap cannot be
 * scaled as a part. Instead every vertex is moved outward from the strap ring's centre, within the
 * ring's cross-section (X/Y of the model frame, see [WatchRenderer]); the ring's length along the
 * arm (Z) is untouched. The move fades out toward the case (which sits on the +X side of the
 * opening), so the case keeps its size and nothing tears.
 *
 * Works on a copy of the GLB bytes, in memory, before Filament parses them; the cached file is never
 * changed. Anything unexpected (compressed or quantized meshes, odd layout) returns the original
 * bytes unchanged.
 */
object StrapScaler {
    private const val MAGIC_GLTF = 0x46546C67
    private const val CHUNK_JSON = 0x4E4F534A
    private const val CHUNK_BIN = 0x004E4942
    private const val FLOAT = 5126
    private val UNSUPPORTED = setOf(
        "KHR_draco_mesh_compression", "EXT_meshopt_compression", "KHR_mesh_quantization",
    )

    fun apply(glb: ByteArray, fit: ModelFit, factor: Double): ByteArray {
        if (factor == 1.0 || glb.size < 28) return glb
        return try {
            scale(glb, fit, factor) ?: glb
        } catch (e: Throwable) {
            glb
        }
    }

    private fun scale(original: ByteArray, fit: ModelFit, factor: Double): ByteArray? {
        val data = original.copyOf()
        val bb = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        if (bb.getInt(0) != MAGIC_GLTF) return null
        val jsonLen = bb.getInt(12)
        if (bb.getInt(16) != CHUNK_JSON) return null
        val json = JSONObject(String(data, 20, jsonLen, Charsets.UTF_8))

        json.optJSONArray("extensionsUsed")?.let { ext ->
            for (i in 0 until ext.length()) if (ext.getString(i) in UNSUPPORTED) return null
        }
        val binHeader = 20 + jsonLen
        if (binHeader + 8 > data.size || bb.getInt(binHeader + 4) != CHUNK_BIN) return null
        val binStart = binHeader + 8

        val accessors = json.getJSONArray("accessors")
        val views = json.getJSONArray("bufferViews")
        val meshes = json.getJSONArray("meshes")

        // Each POSITION accessor once, even if several primitives share it.
        val positionAccessors = LinkedHashSet<Int>()
        for (m in 0 until meshes.length()) {
            val prims = meshes.getJSONObject(m).getJSONArray("primitives")
            for (p in 0 until prims.length()) {
                val attrs = prims.getJSONObject(p).getJSONObject("attributes")
                if (attrs.has("POSITION")) positionAccessors.add(attrs.getInt("POSITION"))
            }
        }

        // Full strength on the strap side of the opening, fading to nothing just past its case side.
        val top = fit.holeCx + fit.holeHalfX
        val lo = top - 0.36 * fit.holeHalfX
        val hi = top + 0.20 * fit.holeHalfX
        val cx = fit.holeCx
        var moved = 0

        for (idx in positionAccessors) {
            val a = accessors.getJSONObject(idx)
            if (a.getInt("componentType") != FLOAT || a.getString("type") != "VEC3") continue
            if (a.has("sparse") || !a.has("bufferView")) continue
            val view = views.getJSONObject(a.getInt("bufferView"))
            if (view.optInt("buffer", 0) != 0) continue
            val stride = view.optInt("byteStride", 0).let { if (it == 0) 12 else it }
            val base = binStart + view.optInt("byteOffset", 0) + a.optInt("byteOffset", 0)
            val count = a.getInt("count")
            if (base + (count - 1).toLong() * stride + 12 > data.size) continue

            for (n in 0 until count) {
                val o = base + n * stride
                val x = bb.getFloat(o).toDouble()
                val y = bb.getFloat(o + 4).toDouble()
                val t = ((x - lo) / (hi - lo)).coerceIn(0.0, 1.0)
                val w = 1.0 - t * t * (3.0 - 2.0 * t) // 1 on the strap, 0 on the case
                if (w <= 0.0) continue
                val k = 1.0 + (factor - 1.0) * w
                bb.putFloat(o, (cx + (x - cx) * k).toFloat())
                bb.putFloat(o + 4, (y * k).toFloat())
                moved++
            }
        }
        return if (moved > 0) data else null
    }
}
