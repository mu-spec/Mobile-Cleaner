package com.mobilecleaner.app

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Read-only discovery of user-visible files through MediaStore.
 *
 * Phase 6 only reads metadata: name, path/URI, size, type, and date. Nothing
 * is opened, moved, or deleted here.
 */
class FileScannerBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mobilecleaner.app/file_scanner"

        private const val CATEGORY_IMAGES = "images"
        private const val CATEGORY_VIDEOS = "videos"
        private const val CATEGORY_AUDIO = "audio"
        private const val CATEGORY_DOCUMENTS = "documents"
        private const val CATEGORY_DOWNLOADS = "downloads"

        private const val DEFAULT_LIMIT_PER_CATEGORY = 500
        private const val MAX_LIMIT_PER_CATEGORY = 5000

        /** Extensions treated as documents when a MIME type is missing. */
        private val DOCUMENT_EXTENSIONS = setOf(
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "txt", "rtf", "csv", "odt", "ods", "odp", "epub",
            "md", "json", "xml", "zip", "rar", "7z", "tar", "gz", "apk",
        )

        private val DOCUMENT_MIME_PREFIXES = listOf(
            "application/pdf",
            "application/msword",
            "application/vnd.",
            "application/rtf",
            "application/epub",
            "application/zip",
            "application/x-rar",
            "application/x-7z",
            "application/vnd.android.package-archive",
            "text/",
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "scanFiles") {
            result.notImplemented()
            return
        }

        try {
            val requested = (call.argument<List<String>>("categories")
                ?: listOf(
                    CATEGORY_IMAGES,
                    CATEGORY_VIDEOS,
                    CATEGORY_AUDIO,
                    CATEGORY_DOCUMENTS,
                    CATEGORY_DOWNLOADS,
                ))
            val limit = (call.argument<Int>("limitPerCategory") ?: DEFAULT_LIMIT_PER_CATEGORY)
                .coerceIn(1, MAX_LIMIT_PER_CATEGORY)
            val minSizeBytes = (call.argument<Number>("minSizeBytes")?.toLong() ?: 0L)
                .coerceAtLeast(0L)
            val sortOrder = call.argument<String>("sortOrder") ?: "size_desc"

            val startedAt = System.currentTimeMillis()
            val files = mutableListOf<Map<String, Any?>>()
            var truncated = false

            for (category in requested) {
                val rows = when (category) {
                    CATEGORY_IMAGES -> queryMedia(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                        CATEGORY_IMAGES, limit, minSizeBytes, sortOrder, null, null,
                    )
                    CATEGORY_VIDEOS -> queryMedia(
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                        CATEGORY_VIDEOS, limit, minSizeBytes, sortOrder, null, null,
                    )
                    CATEGORY_AUDIO -> queryMedia(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        CATEGORY_AUDIO, limit, minSizeBytes, sortOrder, null, null,
                    )
                    CATEGORY_DOCUMENTS -> queryDocuments(limit, minSizeBytes, sortOrder)
                    CATEGORY_DOWNLOADS -> queryDownloads(limit, minSizeBytes, sortOrder)
                    else -> emptyList()
                }
                if (rows.size >= limit) {
                    truncated = true
                }
                files.addAll(rows)
            }

            result.success(
                mapOf(
                    "files" to files,
                    "truncated" to truncated,
                    "durationMillis" to (System.currentTimeMillis() - startedAt),
                ),
            )
        } catch (security: SecurityException) {
            result.error(
                "SCAN_PERMISSION_DENIED",
                "Storage permission is required to scan files.",
                security.message,
            )
        } catch (error: Exception) {
            result.error("SCAN_FAILED", "Unable to scan device files.", error.message)
        }
    }

    // ---------------------------------------------------------------- queries

    private fun queryMedia(
        collection: Uri,
        category: String,
        limit: Int,
        minSizeBytes: Long,
        sortOrder: String,
        extraSelection: String?,
        extraArgs: Array<String>?,
    ): List<Map<String, Any?>> {
        val selectionParts = mutableListOf<String>()
        val selectionArgs = mutableListOf<String>()

        if (minSizeBytes > 0) {
            selectionParts += "${MediaStore.MediaColumns.SIZE} >= ?"
            selectionArgs += minSizeBytes.toString()
        } else {
            selectionParts += "${MediaStore.MediaColumns.SIZE} > 0"
        }
        if (extraSelection != null) {
            selectionParts += extraSelection
            extraArgs?.let { selectionArgs.addAll(it) }
        }

        return runQuery(
            collection = collection,
            category = category,
            selection = selectionParts.joinToString(" AND "),
            selectionArgs = selectionArgs.toTypedArray(),
            limit = limit,
            sortOrder = sortOrder,
        )
    }

    private fun queryDocuments(
        limit: Int,
        minSizeBytes: Long,
        sortOrder: String,
    ): List<Map<String, Any?>> {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            @Suppress("DEPRECATION")
            MediaStore.Files.getContentUri("external")
        }

        val selectionParts = mutableListOf<String>()
        val selectionArgs = mutableListOf<String>()

        selectionParts += if (minSizeBytes > 0) {
            selectionArgs += minSizeBytes.toString()
            "${MediaStore.MediaColumns.SIZE} >= ?"
        } else {
            "${MediaStore.MediaColumns.SIZE} > 0"
        }

        // Exclude rows already covered by the image/video/audio categories.
        selectionParts += "${MediaStore.Files.FileColumns.MEDIA_TYPE} NOT IN (?, ?, ?)"
        selectionArgs += MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString()
        selectionArgs += MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString()
        selectionArgs += MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO.toString()

        val rows = runQuery(
            collection = collection,
            category = CATEGORY_DOCUMENTS,
            selection = selectionParts.joinToString(" AND "),
            selectionArgs = selectionArgs.toTypedArray(),
            // Over-fetch, then keep only document-like rows.
            limit = limit * 3,
            sortOrder = sortOrder,
        )

        return rows.filter { isDocument(it) }.take(limit)
    }

    private fun queryDownloads(
        limit: Int,
        minSizeBytes: Long,
        sortOrder: String,
    ): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val selectionParts = mutableListOf<String>()
            val selectionArgs = mutableListOf<String>()
            selectionParts += if (minSizeBytes > 0) {
                selectionArgs += minSizeBytes.toString()
                "${MediaStore.MediaColumns.SIZE} >= ?"
            } else {
                "${MediaStore.MediaColumns.SIZE} > 0"
            }

            val rows = runQuery(
                collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                category = CATEGORY_DOWNLOADS,
                selection = selectionParts.joinToString(" AND "),
                selectionArgs = selectionArgs.toTypedArray(),
                limit = limit,
                sortOrder = sortOrder,
            )
            if (rows.isNotEmpty()) {
                return rows
            }
        }

        // Legacy fallback: walk the public Downloads directory directly.
        @Suppress("DEPRECATION")
        val downloadsDir =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        return walkDirectory(downloadsDir, limit, minSizeBytes, sortOrder)
    }

    private fun runQuery(
        collection: Uri,
        category: String,
        selection: String,
        selectionArgs: Array<String>,
        limit: Int,
        sortOrder: String,
    ): List<Map<String, Any?>> {
        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.DATA,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection += MediaStore.MediaColumns.RELATIVE_PATH
        }

        val order = "${sortColumn(sortOrder)} LIMIT $limit"
        val resolver: ContentResolver = context.contentResolver
        val results = mutableListOf<Map<String, Any?>>()

        val cursor: Cursor = resolver.query(
            collection,
            projection.toTypedArray(),
            selection.ifEmpty { null },
            if (selectionArgs.isEmpty()) null else selectionArgs,
            order,
        ) ?: return results

        cursor.use { rows ->
            val idColumn = rows.getColumnIndex(MediaStore.MediaColumns._ID)
            val nameColumn = rows.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeColumn = rows.getColumnIndex(MediaStore.MediaColumns.SIZE)
            val mimeColumn = rows.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
            val dateColumn = rows.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
            val dataColumn = rows.getColumnIndex(MediaStore.MediaColumns.DATA)
            val relativeColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                rows.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            } else {
                -1
            }

            while (rows.moveToNext() && results.size < limit) {
                val id = if (idColumn >= 0) rows.getLong(idColumn) else continue
                val path = if (dataColumn >= 0) rows.getString(dataColumn).orEmpty() else ""
                var name = if (nameColumn >= 0) rows.getString(nameColumn).orEmpty() else ""
                if (name.isEmpty()) {
                    name = path.substringAfterLast('/')
                }
                if (name.isEmpty()) continue

                // DATE_MODIFIED is in seconds since epoch.
                val dateSeconds = if (dateColumn >= 0) rows.getLong(dateColumn) else 0L

                results += mapOf(
                    "id" to id.toString(),
                    "name" to name,
                    "path" to path,
                    "uri" to ContentUris.withAppendedId(collection, id).toString(),
                    "sizeBytes" to if (sizeColumn >= 0) rows.getLong(sizeColumn) else 0L,
                    "mimeType" to if (mimeColumn >= 0) rows.getString(mimeColumn) else null,
                    "dateModifiedMillis" to dateSeconds * 1000L,
                    "relativePath" to if (relativeColumn >= 0) {
                        rows.getString(relativeColumn)
                    } else {
                        path.substringBeforeLast('/', "")
                    },
                    "category" to category,
                )
            }
        }

        return results
    }

    /** Legacy pre-Q fallback used only for the Downloads folder. */
    private fun walkDirectory(
        directory: File?,
        limit: Int,
        minSizeBytes: Long,
        sortOrder: String,
    ): List<Map<String, Any?>> {
        if (directory == null || !directory.isDirectory || !directory.canRead()) {
            return emptyList()
        }

        val collected = mutableListOf<File>()
        val queue = ArrayDeque<File>()
        queue.add(directory)
        var visited = 0

        while (queue.isNotEmpty() && collected.size < limit * 4 && visited < 20_000) {
            val current = queue.removeFirst()
            visited++
            val children = current.listFiles() ?: continue
            for (child in children) {
                if (child.isDirectory) {
                    queue.add(child)
                } else if (child.length() > 0 && child.length() >= minSizeBytes) {
                    collected += child
                }
            }
        }

        val sorted = when (sortOrder) {
            "date_desc" -> collected.sortedByDescending { it.lastModified() }
            "name_asc" -> collected.sortedBy { it.name.lowercase() }
            else -> collected.sortedByDescending { it.length() }
        }

        return sorted.take(limit).map { file ->
            mapOf(
                "id" to file.absolutePath,
                "name" to file.name,
                "path" to file.absolutePath,
                "uri" to Uri.fromFile(file).toString(),
                "sizeBytes" to file.length(),
                "mimeType" to null,
                "dateModifiedMillis" to file.lastModified(),
                "relativePath" to file.parent.orEmpty(),
                "category" to CATEGORY_DOWNLOADS,
            )
        }
    }

    // ---------------------------------------------------------------- helpers

    private fun sortColumn(sortOrder: String): String = when (sortOrder) {
        "date_desc" -> "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
        "name_asc" -> "${MediaStore.MediaColumns.DISPLAY_NAME} ASC"
        else -> "${MediaStore.MediaColumns.SIZE} DESC"
    }

    private fun isDocument(row: Map<String, Any?>): Boolean {
        val mime = (row["mimeType"] as? String)?.lowercase()
        if (mime != null && DOCUMENT_MIME_PREFIXES.any { mime.startsWith(it) }) {
            return true
        }
        val name = (row["name"] as? String)?.lowercase() ?: return false
        val extension = name.substringAfterLast('.', "")
        return extension.isNotEmpty() && DOCUMENT_EXTENSIONS.contains(extension)
    }
}
