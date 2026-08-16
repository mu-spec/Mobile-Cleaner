package com.mobilecleaner.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * User-granted folder access through the Storage Access Framework.
 *
 * Scoped storage hides non-media files (documents, archives, APKs) that other
 * apps created, so MediaStore alone cannot list them. SAF is the Play-compliant
 * way to read them: the user picks a folder and the grant is persisted.
 *
 * This deliberately avoids MANAGE_EXTERNAL_STORAGE, which Play restricts to a
 * narrow set of app categories.
 */
class SafAccessBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mobilecleaner.app/saf"
        const val REQUEST_CODE_OPEN_TREE = 4711

        /**
         * Android 11 blocks tree grants on these, so the picker must not start
         * there or the confirm button is greyed out.
         *
         * See "Document access restrictions" in the Android 11 storage docs.
         */
        private val BLOCKED_TREE_SUFFIXES = listOf(
            "primary:",
            "primary:Download",
            "primary:Android",
        )
    }

    /** Set while a picker is in flight so the result can be returned to Dart. */
    private var pendingResult: MethodChannel.Result? = null

    var activity: Activity? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getGrantedTrees" -> result.success(grantedTrees())
            "requestTreeAccess" -> requestTreeAccess(call.argument<String>("initialDir"), result)
            "releaseTree" -> {
                releaseTree(call.argument<String>("uri"))
                result.success(grantedTrees())
            }
            "isAccessRequired" -> result.success(isAccessRequired())
            else -> result.notImplemented()
        }
    }

    /**
     * True when the platform hides non-media files from MediaStore, which is
     * every device running Android 10 or newer.
     */
    private fun isAccessRequired(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    /** Persisted read grants, newest first. */
    fun grantedTrees(): List<Map<String, Any?>> {
        return context.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission }
            .map { permission ->
                mapOf(
                    "uri" to permission.uri.toString(),
                    "label" to treeLabel(permission.uri),
                    // Older grants may be read-only; the UI can re-prompt.
                    "canWrite" to permission.isWritePermission,
                )
            }
    }

    /** Human-readable folder name, e.g. `Documents`. */
    private fun treeLabel(uri: Uri): String {
        val id = try {
            DocumentsContract.getTreeDocumentId(uri)
        } catch (error: IllegalArgumentException) {
            null
        } ?: return uri.lastPathSegment.orEmpty()

        val path = id.substringAfter(':', "")
        if (path.isEmpty()) {
            return "Internal storage"
        }
        return path.substringAfterLast('/')
    }

    private fun requestTreeAccess(initialDir: String?, result: MethodChannel.Result) {
        val current = activity
        if (current == null) {
            result.error("NO_ACTIVITY", "No activity is attached.", null)
            return
        }
        if (pendingResult != null) {
            result.error("ALREADY_REQUESTING", "A folder picker is already open.", null)
            return
        }

        val intent = buildOpenTreeIntent(initialDir)
        pendingResult = result
        try {
            current.startActivityForResult(intent, REQUEST_CODE_OPEN_TREE)
        } catch (error: Exception) {
            pendingResult = null
            result.error("PICKER_UNAVAILABLE", "No folder picker is available.", error.message)
        }
    }

    private fun buildOpenTreeIntent(initialDir: String?): Intent {
        val intent: Intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val storage = context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
            storage.primaryStorageVolume.createOpenDocumentTreeIntent()
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        }

        // Write access is required for deletion. `DocumentsContract
        // .deleteDocument` throws SecurityException on a read-only grant,
        // which surfaced to users as "Access to this file was denied".
        intent.addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )

        // Suggest a sensible starting folder. Never Download or a volume root,
        // because Android 11+ refuses to grant those.
        val target = initialDir?.takeIf { it.isNotBlank() && !isBlockedTarget(it) }
        if (target != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val initialUri = intent
                .getParcelableExtra<Uri>(DocumentsContract.EXTRA_INITIAL_URI)
                ?.toString()
                ?.replace("/root/", "/document/")
                ?.plus("%3A" + Uri.encode(target))
            if (initialUri != null) {
                intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(initialUri))
            }
        }
        return intent
    }

    private fun isBlockedTarget(target: String): Boolean {
        val normalised = target.trim('/')
        return normalised.isEmpty() ||
            normalised.equals("Download", ignoreCase = true) ||
            normalised.equals("Downloads", ignoreCase = true) ||
            normalised.equals("Android", ignoreCase = true)
    }

    /** Called from `MainActivity.onActivityResult`. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_OPEN_TREE) {
            return false
        }
        val result = pendingResult
        pendingResult = null

        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            // Cancelling is a normal outcome, not an error.
            result?.success(grantedTrees())
            return true
        }

        try {
            context.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (error: SecurityException) {
            result?.error("GRANT_FAILED", "Could not keep access to that folder.", error.message)
            return true
        }

        result?.success(grantedTrees())
        return true
    }

    private fun releaseTree(uriString: String?) {
        val uri = uriString?.let(Uri::parse) ?: return
        try {
            context.contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (error: SecurityException) {
            // Already gone; nothing to release.
        }
    }
}
