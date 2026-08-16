package com.mobilecleaner.app

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
class FileScannerBridge(
    private val context: Context,
    private val safAccess: SafAccessBridge,
) : MethodChannel.MethodCallHandler {

    private val safScanner = SafDocumentScanner(context)

    companion object {
        const val CHANNEL = "com.mobilecleaner.app/file_scanner"

        private const val CATEGORY_IMAGES = "images"
        private const val CATEGORY_VIDEOS = "videos"
        private const val CATEGORY_AUDIO = "audio"
        private const val CATEGORY_DOCUMENTS = "documents"
        private const val CATEGORY_DOWNLOADS = "downloads"
        private const val CATEGORY_APKS = "apks"

        private const val DEFAULT_LIMIT_PER_CATEGORY = 500
        private const val MAX_LIMIT_PER_CATEGORY = 5000

        /** Categories scoped storage hides from MediaStore. */
        private val NON_MEDIA_CATEGORIES = setOf(
            CATEGORY_DOCUMENTS,
            CATEGORY_DOWNLOADS,
            CATEGORY_APKS,
        )

        private const val APK_MIME = "application/vnd.android.package-archive"
        private const val APK_EXTENSION = "apk"

        /** Extensions treated as documents when a MIME type is missing. */
        private val DOCUMENT_EXTENSIONS = setOf(
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "txt", "rtf", "csv", "odt", "ods", "odp", "epub",
            "md", "json", "xml", "zip", "rar", "7z", "tar", "gz",
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
                        includeDuration = true,
                    )
                    CATEGORY_AUDIO -> queryMedia(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        CATEGORY_AUDIO, limit, minSizeBytes, sortOrder, null, null,
                    )
                    CATEGORY_DOCUMENTS -> mergeNonMedia(
                        CATEGORY_DOCUMENTS,
                        queryDocuments(limit, minSizeBytes, sortOrder),
                        limit,
                        minSizeBytes,
                        sortOrder,
                    ) { name, mime, _ -> isDocumentLike(name, mime) }
                    CATEGORY_DOWNLOADS -> mergeNonMedia(
                        CATEGORY_DOWNLOADS,
                        queryDownloads(limit, minSizeBytes, sortOrder),
                        limit,
                        minSizeBytes,
                        sortOrder,
                    ) { _, _, documentId -> isInDownloads(documentId) }
                    CATEGORY_APKS -> mergeNonMedia(
                        CATEGORY_APKS,
                        queryApks(limit, minSizeBytes, sortOrder),
                        limit,
                        minSizeBytes,
                        sortOrder,
                    ) { name, mime, _ -> isApkLike(name, mime) }
                    else -> emptyList()
                }
                if (rows.size >= limit) {
                    truncated = true
                }
                files.addAll(rows)
            }

            val grantedTrees = safAccess.grantedTrees()
            val needsAccess = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                grantedTrees.isEmpty() &&
                requested.any { it in NON_MEDIA_CATEGORIES }

            result.success(
                mapOf(
                    "files" to files,
                    "truncated" to truncated,
                    "durationMillis" to (System.currentTimeMillis() - startedAt),
                    // Scoped storage hides other apps' non-media files, so the
                    // UI needs to know when a folder grant would reveal more.
                    "needsFolderAccess" to needsAccess,
                    "grantedFolders" to grantedTrees,
                ),
            )
        } catch (security: SecurityException) {
            result.error(
                "SCAN_PERMISSION_DENIED",
                "Storage permission is required to scan files.",
                security.message,
            )
        } catch (error: Exception) {
            // Include the exception type: a bare message is often null, which
            // left the UI showing "We could not scan your files" with nothing
            // to diagnose from. This is how the API 30 "Invalid token LIMIT"
            // failure stayed invisible until a user reported it.
            result.error(
                "SCAN_FAILED",
                "Unable to scan device files.",
                "${error.javaClass.simpleName}: ${error.message}",
            )
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
        includeDuration: Boolean = false,
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
            includeDuration = includeDuration,
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

        // APKs have their own category, so keep them out of Documents.
        return rows.filter { isDocument(it) && !isApk(it) }.take(limit)
    }

    /**
     * Installer packages anywhere in shared storage.
     *
     * Queried by MIME type and by `.apk` name so packages are still found when
     * MediaStore has not classified the row.
     */
    private fun queryApks(
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

        selectionParts += "(${MediaStore.MediaColumns.MIME_TYPE} = ? OR " +
            "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?)"
        selectionArgs += APK_MIME
        selectionArgs += "%.$APK_EXTENSION"

        val rows = runQuery(
            collection = collection,
            category = CATEGORY_APKS,
            selection = selectionParts.joinToString(" AND "),
            selectionArgs = selectionArgs.toTypedArray(),
            limit = limit,
            sortOrder = sortOrder,
        )

        // The LIKE clause can match names such as "notes.apk.txt".
        return rows.filter { isApk(it) }
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

        // Direct file access only works before scoped storage. On Android 10+
        // this walk reads nothing, and SAF is the supported route instead.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return emptyList()
        }

        // Legacy fallback: walk the public Downloads directory directly.
        @Suppress("DEPRECATION")
        val downloadsDir =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        return walkDirectory(downloadsDir, limit, minSizeBytes, sortOrder)
    }

    /**
     * Runs a MediaStore query with a row limit, on every supported API level.
     *
     * ## Why this is not just `"$column DESC LIMIT $n"`
     *
     * Appending `LIMIT` to the sort-order string is the classic MediaStore
     * idiom, and it worked for years. Android 11 (API 30) added a SQL token
     * validator to `MediaProvider` that rejects it outright:
     *
     * ```
     * java.lang.IllegalArgumentException: Invalid token LIMIT
     * ```
     *
     * The check applies to apps *targeting* API 30+, so the same APK behaves
     * differently depending on `targetSdk`, and the crash only appears on
     * newer devices. Every scan threw, which surfaced in the app as
     * "We could not scan your files" on Android 11, 12, 13 and 14.
     *
     * On API 30+ the limit therefore travels as a real query argument in a
     * [Bundle]. Below that, the legacy string is still the only option.
     */
    private fun queryWithLimit(
        resolver: ContentResolver,
        collection: Uri,
        projection: Array<String>,
        selection: String?,
        selectionArgs: Array<String>?,
        order: String,
        limit: Int,
    ): Cursor? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val args = Bundle().apply {
                putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
                putString(ContentResolver.QUERY_ARG_SQL_SORT_ORDER, order)
                if (selection != null) {
                    putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                }
                if (selectionArgs != null) {
                    putStringArray(
                        ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS,
                        selectionArgs,
                    )
                }
            }
            return resolver.query(collection, projection, args, null)
        }

        @Suppress("DEPRECATION")
        return resolver.query(
            collection,
            projection,
            selection,
            selectionArgs,
            "$order LIMIT $limit",
        )
    }

    private fun runQuery(
        collection: Uri,
        category: String,
        selection: String,
        selectionArgs: Array<String>,
        limit: Int,
        sortOrder: String,
        includeDuration: Boolean = false,
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
        // Only the video collection is guaranteed to expose DURATION on every
        // API level, so it is requested per-query rather than always.
        if (includeDuration) {
            projection += MediaStore.Video.Media.DURATION
        }

        val resolver: ContentResolver = context.contentResolver
        val results = mutableListOf<Map<String, Any?>>()

        val cursor: Cursor = queryWithLimit(
            resolver = resolver,
            collection = collection,
            projection = projection.toTypedArray(),
            selection = selection.ifEmpty { null },
            selectionArgs = if (selectionArgs.isEmpty()) null else selectionArgs,
            order = sortColumn(sortOrder),
            limit = limit,
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
            val durationColumn = if (includeDuration) {
                rows.getColumnIndex(MediaStore.Video.Media.DURATION)
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
                    // Deliberately not "durationMillis": the scan payload
                    // already uses that key for how long the scan took.
                    // Null rather than zero when unknown, so a video whose
                    // length MediaStore never resolved is not shown as 0:00.
                    "videoDurationMillis" to if (durationColumn >= 0 &&
                        !rows.isNull(durationColumn)
                    ) {
                        rows.getLong(durationColumn).takeIf { it > 0L }
                    } else {
                        null
                    },
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

    /**
     * Combines MediaStore rows with SAF rows for a non-media category.
     *
     * MediaStore only reports non-media files this app itself created, so on
     * Android 10+ it under-reports badly. Any folder the user granted through
     * SAF is walked as well, and the two sets are merged and de-duplicated by
     * name plus size, since the same file has a different URI in each source.
     */
    private fun mergeNonMedia(
        category: String,
        mediaStoreRows: List<Map<String, Any?>>,
        limit: Int,
        minSizeBytes: Long,
        sortOrder: String,
        accept: (name: String, mimeType: String?, documentId: String) -> Boolean,
    ): List<Map<String, Any?>> {
        val trees = grantedTreeUris()
        if (trees.isEmpty()) {
            return mediaStoreRows
        }

        val safRows = try {
            safScanner
                .scan(trees, minSizeBytes, limit) { name, mime, documentId ->
                    accept(name, mime, documentId)
                }
                .map { row -> row + ("category" to category) }
        } catch (error: Exception) {
            // A broken grant must not fail the whole scan.
            emptyList()
        }

        val combined = mutableListOf<Map<String, Any?>>()
        val seen = mutableSetOf<String>()
        for (row in mediaStoreRows + safRows) {
            val name = (row["name"] as? String)?.lowercase().orEmpty()
            val size = (row["sizeBytes"] as? Number)?.toLong() ?: 0L
            if (!seen.add("$name:$size")) continue
            combined += row
        }

        return sortRows(combined, sortOrder).take(limit)
    }

    private fun grantedTreeUris(): List<Uri> {
        return safAccess.grantedTrees().mapNotNull { tree ->
            (tree["uri"] as? String)?.let(Uri::parse)
        }
    }

    private fun sortRows(
        rows: List<Map<String, Any?>>,
        sortOrder: String,
    ): List<Map<String, Any?>> {
        fun size(row: Map<String, Any?>) = (row["sizeBytes"] as? Number)?.toLong() ?: 0L
        fun modified(row: Map<String, Any?>) =
            (row["dateModifiedMillis"] as? Number)?.toLong() ?: 0L
        fun name(row: Map<String, Any?>) = (row["name"] as? String)?.lowercase().orEmpty()

        return when (sortOrder) {
            "date_desc" -> rows.sortedByDescending { modified(it) }
            "name_asc" -> rows.sortedBy { name(it) }
            else -> rows.sortedByDescending { size(it) }
        }
    }

    /** Name/MIME classifier shared by the MediaStore and SAF paths. */
    private fun isDocumentLike(name: String, mimeType: String?): Boolean {
        if (isApkLike(name, mimeType)) return false
        val mime = mimeType?.lowercase()
        if (mime != null && DOCUMENT_MIME_PREFIXES.any { mime.startsWith(it) }) {
            return true
        }
        val extension = name.lowercase().substringAfterLast('.', "")
        return extension.isNotEmpty() && DOCUMENT_EXTENSIONS.contains(extension)
    }

    /**
     * True when a SAF document id points inside a Download folder.
     *
     * Document ids look like `primary:Download/sub/file.zip`, so the folder
     * segment is compared rather than the whole string, which stops a name
     * such as `MyDownloads` from matching.
     */
    private fun isInDownloads(documentId: String): Boolean {
        val path = documentId.substringAfter(':', "")
        if (path.isEmpty()) return false
        return path.split('/').dropLast(1).any { segment ->
            segment.equals("Download", ignoreCase = true) ||
                segment.equals("Downloads", ignoreCase = true)
        }
    }

    private fun isApkLike(name: String, mimeType: String?): Boolean {
        if (mimeType?.lowercase() == APK_MIME) return true
        return name.lowercase().substringAfterLast('.', "") == APK_EXTENSION
    }

    /** Row wrapper over [isApkLike] so both sources share one rule. */
    private fun isApk(row: Map<String, Any?>): Boolean {
        val name = row["name"] as? String ?: return false
        return isApkLike(name, row["mimeType"] as? String)
    }

    /** Row wrapper over [isDocumentLike] so both sources share one rule. */
    private fun isDocument(row: Map<String, Any?>): Boolean {
        val name = row["name"] as? String ?: return false
        return isDocumentLike(name, row["mimeType"] as? String)
    }
}
