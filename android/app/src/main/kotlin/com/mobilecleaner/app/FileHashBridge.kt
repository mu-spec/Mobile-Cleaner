package com.mobilecleaner.app

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Hashes file contents so exact duplicates can be identified.
 *
 * Only ever called for files that already share a byte size, so the expensive
 * read is limited to genuine candidates.
 *
 * Hashing streams through a fixed buffer rather than loading the file, because
 * a duplicate set can include multi-gigabyte video and reading one into memory
 * would kill the process. Work runs on a background pool so the UI thread is
 * never blocked.
 *
 * Every failure resolves to `null` for that file rather than an error: an
 * unreadable file simply cannot be proven to be a duplicate, and must not be
 * offered for deletion.
 */
class FileHashBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mobilecleaner.app/hash"

        /** SHA-256: collisions are not a practical concern for file identity. */
        private const val ALGORITHM = "SHA-256"

        private const val BUFFER_BYTES = 64 * 1024

        /** Safety valve so one request cannot hash an entire library. */
        private const val MAX_FILES_PER_CALL = 400
    }

    private val executor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "hashFiles") {
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
                        hashUri(raw)
                    } catch (error: Throwable) {
                        // OutOfMemoryError is conceivable on a hostile file.
                        null
                    }
                    // Unreadable files are omitted, never guessed at.
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

    /** Streams the file through the digest, returning lowercase hex. */
    private fun hashUri(raw: String): String? {
        val uri: Uri = Uri.parse(raw)
        val digest = MessageDigest.getInstance(ALGORITHM)

        context.contentResolver.openInputStream(uri)?.use { stream ->
            val buffer = ByteArray(BUFFER_BYTES)
            while (true) {
                val read = stream.read(buffer)
                if (read <= 0) {
                    break
                }
                digest.update(buffer, 0, read)
            }
        } ?: return null

        return digest.digest().joinToString("") { byte ->
            "%02x".format(byte)
        }
    }

    /** Releases the background pool when the engine goes away. */
    fun dispose() {
        executor.shutdown()
    }
}
