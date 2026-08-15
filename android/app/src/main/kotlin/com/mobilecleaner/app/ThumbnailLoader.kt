package com.mobilecleaner.app

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Generates thumbnails for media files through MediaStore.
 *
 * Decoding happens on a background pool because thumbnailing touches disk and
 * would otherwise jank the UI while a list scrolls. Every failure resolves to
 * `null` so the Dart side can quietly fall back to a category icon.
 */
class ThumbnailLoader(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mobilecleaner.app/thumbnails"

        private const val DEFAULT_SIZE = 128
        private const val MAX_SIZE = 512
        private const val JPEG_QUALITY = 80
    }

    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "getThumbnail") {
            result.notImplemented()
            return
        }

        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrEmpty()) {
            result.success(null)
            return
        }
        val size = (call.argument<Int>("size") ?: DEFAULT_SIZE).coerceIn(32, MAX_SIZE)
        val category = call.argument<String>("category").orEmpty()

        try {
            executor.execute {
                val bytes = try {
                    loadThumbnail(uriString, size, category)
                } catch (error: Throwable) {
                    // OutOfMemoryError is a real possibility on huge media.
                    null
                }
                mainHandler.post { result.success(bytes) }
            }
        } catch (rejected: RejectedExecutionException) {
            // The activity is going away; answer immediately rather than crash.
            result.success(null)
        }
    }

    private fun loadThumbnail(uriString: String, size: Int, category: String): ByteArray? {
        val uri: Uri = Uri.parse(uriString)

        val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            context.contentResolver.loadThumbnail(uri, Size(size, size), null)
        } else {
            legacyThumbnail(uri, category)
        }

        if (bitmap == null) {
            return null
        }

        return try {
            ByteArrayOutputStream().use { stream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, stream)
                stream.toByteArray()
            }
        } finally {
            bitmap.recycle()
        }
    }

    /** Pre-Android-10 devices need the per-collection thumbnail APIs. */
    @Suppress("DEPRECATION")
    private fun legacyThumbnail(uri: Uri, category: String): Bitmap? {
        val id = uri.lastPathSegment?.toLongOrNull() ?: return null
        return when (category) {
            "videos" -> MediaStore.Video.Thumbnails.getThumbnail(
                context.contentResolver,
                id,
                MediaStore.Video.Thumbnails.MICRO_KIND,
                null,
            )
            "images" -> MediaStore.Images.Thumbnails.getThumbnail(
                context.contentResolver,
                id,
                MediaStore.Images.Thumbnails.MICRO_KIND,
                null,
            )
            else -> null
        }
    }

    /** Releases the background pool when the engine goes away. */
    fun dispose() {
        executor.shutdown()
    }
}
