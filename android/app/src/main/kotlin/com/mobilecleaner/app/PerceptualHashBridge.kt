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
 * Computes perceptual hashes so visually similar photos can be grouped.
 *
 * This is the opposite problem to [FileHashBridge]. SHA-256 answers "are these
 * the same bytes"; a one-pixel change makes it a different file. A perceptual
 * hash answers "do these look the same", which is what a burst of nearly
 * identical shots requires.
 *
 * Two independent 64-bit hashes are returned per image, concatenated as 32
 * lowercase hex characters:
 *
 *  - **dHash** (first 16 chars) — compares each pixel to its right-hand
 *    neighbour on a 9x8 grid. It encodes gradient direction, so it is largely
 *    unaffected by brightness and exposure changes between shots.
 *  - **aHash** (last 16 chars) — compares each pixel of an 8x8 grid to the
 *    frame's mean. Cruder, and used only as a second opinion: requiring both
 *    to agree cuts the false positives dHash alone produces on flat images
 *    such as sky, snow, or a blank wall.
 *
 * Everything is computed on-device. No image, thumbnail, or hash ever leaves
 * the phone, and no network permission is used.
 *
 * Decoding is downsampled through [BitmapFactory.Options.inSampleSize] so a
 * 50 MP photo is never fully decoded into memory — only enough pixels to fill
 * a 32-pixel grid. Any failure resolves to no entry for that image rather than
 * an error: an image that cannot be read must not be presented as similar to
 * anything.
 */
class PerceptualHashBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mobilecleaner.app/perceptual_hash"

        /** dHash needs one extra column to difference against. */
        private const val DHASH_WIDTH = 9
        private const val DHASH_HEIGHT = 8

        /** aHash is a plain 8x8 grid. */
        private const val AHASH_SIDE = 8

        /**
         * Decode target. Comfortably above the 9-pixel grid so downsampling
         * averages real detail rather than aliasing a handful of pixels.
         */
        private const val DECODE_TARGET = 64

        /** Safety valve so one request cannot hash an entire library. */
        private const val MAX_FILES_PER_CALL = 600
    }

    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "hashImages") {
            result.notImplemented()
            return
        }

        val uris = call.argument<List<String>>("uris").orEmpty()
        if (uris.isEmpty()) {
            result.success(emptyMap<String, String>())
            return
        }

        val capped = uris.take(MAX_FILES_PER_CALL)

        try {
            executor.execute {
                val hashes = mutableMapOf<String, String>()
                for (raw in capped) {
                    val hash = try {
                        hashImage(raw)
                    } catch (error: Throwable) {
                        // OutOfMemoryError is conceivable on a hostile file.
                        null
                    }
                    // Unreadable images are omitted, never guessed at.
                    if (hash != null) {
                        hashes[raw] = hash
                    }
                }
                mainHandler.post { result.success(hashes) }
            }
        } catch (rejected: RejectedExecutionException) {
            // The activity is going away; answer rather than crash.
            result.success(emptyMap<String, String>())
        }
    }

    /** Returns 32 hex characters: dHash then aHash, or null if unreadable. */
    private fun hashImage(raw: String): String? {
        val uri: Uri = Uri.parse(raw)
        val decoded = decodeDownsampled(uri) ?: return null

        val grey = try {
            // One scaled bitmap wide enough for dHash; aHash reads a subset.
            greyscaleGrid(decoded, DHASH_WIDTH, DHASH_HEIGHT)
        } finally {
            decoded.recycle()
        }

        val difference = differenceHash(grey)
        val average = averageHash(grey)
        return difference + average
    }

    /**
     * Decodes just enough pixels to fill the hash grid.
     *
     * The bounds-only pass is cheap and avoids allocating the full image, which
     * matters because this runs across hundreds of photos in a row.
     */
    private fun decodeDownsampled(uri: Uri): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, bounds)
        } ?: return null

        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            return null
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSizeFor(bounds.outWidth, bounds.outHeight)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }

        return context.contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, options)
        }
    }

    /** Largest power-of-two reduction that still leaves [DECODE_TARGET]. */
    private fun sampleSizeFor(width: Int, height: Int): Int {
        var sample = 1
        var shortest = minOf(width, height)
        while (shortest / 2 >= DECODE_TARGET) {
            shortest /= 2
            sample *= 2
        }
        return sample
    }

    /**
     * Scales to [width] x [height] and returns greyscale luminance per cell.
     *
     * Rec. 601 luma weights, matching how the eye weighs the channels, so two
     * shots differing only in colour temperature still hash alike.
     */
    private fun greyscaleGrid(source: Bitmap, width: Int, height: Int): IntArray {
        val scaled = Bitmap.createScaledBitmap(source, width, height, true)
        val pixels = IntArray(width * height)
        scaled.getPixels(pixels, 0, width, 0, 0, width, height)
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
        return luma
    }

    /** 64 bits: is each pixel brighter than the one to its right. */
    private fun differenceHash(grey: IntArray): String {
        val bits = BooleanArray(DHASH_HEIGHT * (DHASH_WIDTH - 1))
        var index = 0
        for (row in 0 until DHASH_HEIGHT) {
            for (column in 0 until DHASH_WIDTH - 1) {
                val left = grey[row * DHASH_WIDTH + column]
                val right = grey[row * DHASH_WIDTH + column + 1]
                bits[index++] = left > right
            }
        }
        return toHex(bits)
    }

    /** 64 bits: is each pixel brighter than the frame's mean. */
    private fun averageHash(grey: IntArray): String {
        val bits = BooleanArray(AHASH_SIDE * AHASH_SIDE)
        var total = 0L
        var index = 0
        // Read the leftmost 8 columns of the 9-wide grid.
        for (row in 0 until AHASH_SIDE) {
            for (column in 0 until AHASH_SIDE) {
                total += grey[row * DHASH_WIDTH + column]
            }
        }
        val mean = total / (AHASH_SIDE * AHASH_SIDE)
        for (row in 0 until AHASH_SIDE) {
            for (column in 0 until AHASH_SIDE) {
                bits[index++] = grey[row * DHASH_WIDTH + column] > mean
            }
        }
        return toHex(bits)
    }

    /** Packs 64 bits into 16 lowercase hex characters, most significant first. */
    private fun toHex(bits: BooleanArray): String {
        val builder = StringBuilder(bits.size / 4)
        var nibble = 0
        for (index in bits.indices) {
            nibble = (nibble shl 1) or if (bits[index]) 1 else 0
            if (index % 4 == 3) {
                builder.append("0123456789abcdef"[nibble])
                nibble = 0
            }
        }
        return builder.toString()
    }

    /** Releases the background pool when the engine goes away. */
    fun dispose() {
        executor.shutdown()
    }
}
