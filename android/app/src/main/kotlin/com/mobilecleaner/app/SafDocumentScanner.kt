package com.mobilecleaner.app

import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract

/**
 * Enumerates non-media files from folders the user granted through SAF.
 *
 * Uses `DocumentsContract` queries rather than `DocumentFile`, which issues one
 * IPC per attribute per file and is far too slow for a whole tree.
 */
class SafDocumentScanner(private val context: Context) {

    companion object {
        private const val MAX_DIRECTORIES = 400
        private const val MAX_VISITED_DOCUMENTS = 20_000

        private val PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
    }

    /**
     * Walks every granted tree breadth-first and returns raw file rows.
     *
     * [accept] decides which files are kept, so the caller owns categorisation.
     * It receives the document id as well as the name and MIME type, so a
     * caller can filter on location — the Downloads category needs this to
     * avoid claiming files from an unrelated granted folder.
     *
     * Bounded by [MAX_DIRECTORIES] and [MAX_VISITED_DOCUMENTS] so a pathological
     * folder cannot hang the scan.
     */
    fun scan(
        treeUris: List<Uri>,
        minSizeBytes: Long,
        limit: Int,
        accept: (name: String, mimeType: String?, documentId: String) -> Boolean,
    ): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val seenDocumentIds = mutableSetOf<String>()
        var visited = 0

        for (treeUri in treeUris) {
            if (results.size >= limit) break

            val rootId = try {
                DocumentsContract.getTreeDocumentId(treeUri)
            } catch (error: IllegalArgumentException) {
                continue
            }

            // Breadth-first: shallow files, which users recognise, come first.
            val queue = ArrayDeque<String>()
            queue.add(rootId)
            var directories = 0

            while (queue.isNotEmpty() &&
                results.size < limit &&
                directories < MAX_DIRECTORIES &&
                visited < MAX_VISITED_DOCUMENTS
            ) {
                val parentId = queue.removeFirst()
                directories++

                val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                    treeUri,
                    parentId,
                )

                val cursor: Cursor = try {
                    context.contentResolver.query(childrenUri, PROJECTION, null, null, null)
                } catch (error: SecurityException) {
                    // The grant was revoked while scanning.
                    null
                } catch (error: Exception) {
                    null
                } ?: continue

                cursor.use { rows ->
                    val idColumn = rows.getColumnIndex(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    )
                    val nameColumn = rows.getColumnIndex(
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    )
                    val mimeColumn = rows.getColumnIndex(
                        DocumentsContract.Document.COLUMN_MIME_TYPE,
                    )
                    val sizeColumn = rows.getColumnIndex(
                        DocumentsContract.Document.COLUMN_SIZE,
                    )
                    val modifiedColumn = rows.getColumnIndex(
                        DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                    )

                    while (rows.moveToNext() && results.size < limit) {
                        visited++
                        if (visited >= MAX_VISITED_DOCUMENTS) break

                        val documentId = if (idColumn >= 0) rows.getString(idColumn) else null
                        if (documentId.isNullOrEmpty()) continue

                        val mimeType = if (mimeColumn >= 0) rows.getString(mimeColumn) else null

                        if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                            if (directories + queue.size < MAX_DIRECTORIES) {
                                queue.add(documentId)
                            }
                            continue
                        }

                        val name = if (nameColumn >= 0) {
                            rows.getString(nameColumn).orEmpty()
                        } else {
                            ""
                        }
                        if (name.isEmpty() || !accept(name, mimeType, documentId)) continue

                        val size = if (sizeColumn >= 0 && !rows.isNull(sizeColumn)) {
                            rows.getLong(sizeColumn)
                        } else {
                            0L
                        }
                        if (size <= 0L || size < minSizeBytes) continue

                        // The same file can sit under two granted trees.
                        if (!seenDocumentIds.add(documentId)) continue

                        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                            treeUri,
                            documentId,
                        )

                        results += mapOf(
                            "id" to documentId,
                            "name" to name,
                            // SAF exposes no filesystem path; show the tree path.
                            "path" to documentId.substringAfter(':', documentId),
                            "uri" to documentUri.toString(),
                            "sizeBytes" to size,
                            "mimeType" to mimeType,
                            "dateModifiedMillis" to if (modifiedColumn >= 0) {
                                rows.getLong(modifiedColumn)
                            } else {
                                0L
                            },
                            "relativePath" to documentId
                                .substringAfter(':', "")
                                .substringBeforeLast('/', ""),
                        )
                    }
                }
            }
        }

        return results
    }
}
