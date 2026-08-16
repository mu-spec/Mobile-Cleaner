package com.mobilecleaner.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Measures how good a photo is, so the best shot of a similar set can be
 * suggested.
 *
 * Three measurements per image:
 *
 *  - **width / height** — read from the bounds-only decode pass, so full
 *    resolution is known without decoding a single pixel of image data.
 *  - **sharpness** — variance of the Laplacian over a greyscale downsample.
 *    A sharp photo has strong local intensity changes at edges, so the second
 *    derivative varies a lot; a blurred or out-of-focus photo has soft
 *    transitions and a low variance. This is the standard cheap focus measure
 *    and needs no model, no library, and no network.
 *  - **pixels** — width x height, kept separately so Dart never has to trust
 *    an overflowing multiplication.
 *
 * Called only for photos that already landed in a similar-photo group, which
 * is a small fraction of a library. Everything runs on-device.
 *
 * Sharpness is measured at a fixed working size rather than at native
 * resolution. That is deliberate: Laplacian variance rises with pixel count,
 * so comparing a 12 MP shot against an 8 MP shot at native size would measure
 * resolution twice and call the bigger file sharper regardless of focus.
 * Resolution is scored separately, by Dart.
 *
 * Any failure omits that photo rather than failing the batch: an unmeasured
 * photo simply gets no recommendation, which is safe.
 */
class PhotoQualityBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mobilecleaner.app/photo_quality"

        /**
         * Side length the sharpness measurement works at. Large enough to hold
         * real edge detail, small enough that hundreds of photos stay cheap.
         */
        private const val WORKING_SIDE = 256

        /** Safety valve so one request cannot analyse an entire library. */
        private const val MAX_FILES_PER_CALL = 300
    }

    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "analyzePhotos") {
            result.notImplemented()
            return
        }

        val uris = call.argument<List<String>>("uris").orEmpty()
        if (uris.isEmpty()) {
            result.success(emptyMap<String, Map<String, Any>>())
            return
        }

        val capped = uris.take(MAX_FILES_PER_CALL)

        try {
            executor.execute {
                val measurements = mutableMapOf<String, Map<String, Any>>()
                for (raw in capped) {
                    val measured = try {
                        analyze(raw)
                    } catch (error: Throwable) {
                        // OutOfMemoryError is conceivable on a hostile file.
                        null
                    }
                    if (measured != null) {
                        measurements[raw] = measured
                    }
                }
                mainHandler.post { result.success(measurements) }
            }
        } catch (rejected: RejectedExecutionException) {
            // The activity is going away; answer rather than crash.
            result.success(emptyMap<String, Map<String, Any>>())
        }
    }

    private fun analyze(raw: String): Map<String, Any>? {
        val uri: Uri = Uri.parse(raw)

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, bounds)
        } ?: return null

        val width = bounds.outWidth
        val height = bounds.outHeight
        if (width <= 0 || height <= 0) {
            return null
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(width, height)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, options)
        } ?: return null

        val sharpness = try {
            sharpnessOf(decoded)
        } finally {
            decoded.recycle()
        }

        return mapOf(
            "width" to width,
            "height" to height,
            // Sent as a long so Dart never has to widen a platform int.
            "pixels" to width.toLong() * height.toLong(),
            "sharpness" to sharpness,
        )
    }

    /** Largest power-of-two reduction that still leaves [WORKING_SIDE]. */
    private fun sampleSizeFor(width: Int, height: Int): Int {
        var sample = 1
        var shortest = minOf(width, height)
        while (shortest / 2 >= WORKING_SIDE) {
            shortest /= 2
            sample *= 2
        }
        return sample
    }

    /**
     * Variance of the Laplacian over a greyscale copy, scaled to a fixed grid.
     *
     * The 4-neighbour Laplacian kernel is used:
     *
     * ```
     *      0  1  0
     *      1 -4  1
     *      0  1  0
     * ```
     *
     * Border pixels are skipped rather than clamped, because a clamped border
     * fabricates edges that do not exist and inflates the score of a photo
     * with a plain background.
     */
    private fun sharpnessOf(source: Bitmap): Double {
        val side = WORKING_SIDE
        val scaled = Bitmap.createScaledBitmap(source, side, side, true)
        val pixels = IntArray(side * side)
        scaled.getPixels(pixels, 0, side, 0, 0, side, side)
        if (scaled != source) {
            scaled.recycle()
        }

        val luma = IntArray(pixels.size)
        for (index in pixels.indices) {
            val pixel = pixels[index]
            val red = (pixel shr 16) and 0xFF
            val green = (pixel shr 8) and 0xFF
            val blue = pixel and 0xFF
            luma[index] = (red * 299 + green * 587 + blue * 114) / 1000
        }

        var sum = 0.0
        var sumSquares = 0.0
        var count = 0

        for (row in 1 until side - 1) {
            for (column in 1 until side - 1) {
                val index = row * side + column
                val laplacian = (
                    luma[index - side] +
                        luma[index + side] +
                        luma[index - 1] +
                        luma[index + 1] -
                        4 * luma[index]
                    ).toDouble()
                sum += laplacian
                sumSquares += laplacian * laplacian
                count++
            }
        }

        if (count == 0) {
            return 0.0
        }

        val mean = sum / count
        val variance = (sumSquares / count) - (mean * mean)
        return if (variance > 0.0) variance else 0.0
    }

    /** Releases the background pool when the engine goes away. */
    fun dispose() {
        executor.shutdown()
    }
}
