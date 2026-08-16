package com.mobilecleaner.app

import android.Manifest
import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Deletes user-selected files.
 *
 * Android gates deletion of files this app did not create, and the rules
 * differ by version:
 *
 * - **Android 11+**: `MediaStore.createDeleteRequest` shows one system dialog
 *   for the whole batch. This is the Play-compliant bulk path.
 * - **Android 10**: a `RecoverableSecurityException` carries an `IntentSender`
 *   that must be confirmed per file.
 * - **Android 9 and below**: a plain `ContentResolver.delete` succeeds.
 *
 * SAF document URIs bypass MediaStore entirely and are removed through
 * `DocumentsContract`, which needs no extra dialog because the user already
 * granted write access to that tree.
 *
 * Nothing here deletes without the user having confirmed in-app first; the
 * system dialog is an additional gate, never a replacement for ours.
 */
class DeleteBridge(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mobilecleaner.app/delete"
        const val REQUEST_CODE_DELETE = 4712
        const val REQUEST_CODE_WRITE_PERMISSION = 4713

        private const val SCHEME_CONTENT = "content"
        private const val SCHEME_FILE = "file"

        /** Diagnostics tag. Temporary; see docs/delete-debug-logging.md. */
        private const val DEBUG_TAG = "DELETE_DEBUG"
    }

    var activity: Activity? = null

    /** Set while a system dialog is showing. */
    private var pendingResult: MethodChannel.Result? = null

    /** URIs awaiting the outcome of the current system dialog. */
    private var pendingUris: List<Uri> = emptyList()

    /** Set while the API 28 write-permission dialog is showing. */
    private var pendingPermissionUris: List<Uri> = emptyList()

    /** Files already removed before the dialog was raised. */
    private var deletedBeforePrompt: MutableList<String> = mutableListOf()

    private var failedBeforePrompt: MutableList<Map<String, Any?>> = mutableListOf()

    /**
     * Per-URI metadata supplied by Dart purely so the logs are readable.
     *
     * Deletion never consults this; routing still depends only on the URI.
     */
    private var debugItems: Map<String, Map<*, *>> = emptyMap()

    private fun log(message: String) {
        Log.i(DEBUG_TAG, "[$DEBUG_TAG] $message")
    }

    private fun logError(message: String, error: Throwable) {
        // Log the class, message and full stack trace separately, so a
        // truncated logcat line still shows which exception was thrown.
        Log.e(
            DEBUG_TAG,
            "[$DEBUG_TAG] $message | exceptionClass=${error.javaClass.name} " +
                "| exceptionMessage=${error.message}",
            error,
        )
    }

    /** Everything known about one URI before a strategy is chosen. */
    private fun describe(uri: Uri): String {
        val item = debugItems[uri.toString()]
        val scheme = uri.scheme ?: "none"
        val rawScheme = when (scheme) {
            SCHEME_CONTENT -> "content://"
            SCHEME_FILE -> "file://"
            else -> "raw/$scheme"
        }
        return buildString {
            append("category=").append(item?.get("category") ?: "unknown")
            append(" | name=").append(item?.get("name") ?: "unknown")
            append(" | originalPath=").append(item?.get("path") ?: "unknown")
            append(" | mimeType=").append(item?.get("mimeType") ?: "unknown")
            append(" | sizeBytes=").append(item?.get("sizeBytes") ?: "unknown")
            append(" | uri=").append(uri)
            append(" | scheme=").append(rawScheme)
            append(" | authority=").append(uri.authority ?: "none")
        }
    }

    /** Whether a persisted SAF grant covers this URI, and with what access. */
    private fun describeSafPermission(uri: Uri): String {
        return try {
            val target = uri.toString()
            val match = context.contentResolver.persistedUriPermissions
                .firstOrNull { target.startsWith(it.uri.toString()) }
            if (match == null) {
                "safPermission=none"
            } else {
                "safPermission=yes | safRead=${match.isReadPermission} " +
                    "| safWrite=${match.isWritePermission} " +
                    "| safTree=${match.uri}"
            }
        } catch (error: Exception) {
            "safPermission=error(${error.javaClass.simpleName})"
        }
    }

    /** Whether MediaStore can still see the row. */
    private fun describeMediaStoreLookup(uri: Uri): String {
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns._ID),
                null,
                null,
                null,
            )?.use { cursor ->
                "mediaStoreLookup=ok | rows=${cursor.count}"
            } ?: "mediaStoreLookup=nullCursor"
        } catch (error: Exception) {
            "mediaStoreLookup=failed(${error.javaClass.simpleName}: ${error.message})"
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "deleteFiles") {
            result.notImplemented()
            return
        }

        val rawUris = call.argument<List<String>>("uris").orEmpty()
        if (rawUris.isEmpty()) {
            result.success(emptyResponse())
            return
        }
        if (pendingResult != null) {
            result.error("ALREADY_DELETING", "A delete is already in progress.", null)
            return
        }

        val uris = rawUris.mapNotNull { raw ->
            try {
                Uri.parse(raw)
            } catch (error: Exception) {
                null
            }
        }

        deletedBeforePrompt = mutableListOf()
        failedBeforePrompt = mutableListOf()

        debugItems = call.argument<List<Map<*, *>>>("debugItems")
            .orEmpty()
            .mapNotNull { item ->
                (item["uri"] as? String)?.let { uri -> uri to item }
            }
            .toMap()

        log(
            "===== delete request ===== sdkInt=${Build.VERSION.SDK_INT} " +
                "(${Build.VERSION.RELEASE}) | device=${Build.MANUFACTURER} " +
                "${Build.MODEL} | requested=${uris.size}",
        )

        // Route each URI to the API that can actually delete it.
        val safUris = uris.filter { isSafDocument(it) }
        val fileUris = uris.filter { isDirectFile(it) }
        val mediaUris = uris.filter { !isSafDocument(it) && !isDirectFile(it) }

        for (uri in uris) {
            val branch = when {
                isSafDocument(uri) -> "SAF/DocumentsContract.deleteDocument"
                isDirectFile(uri) -> "DIRECT/File.delete"
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                    "MEDIASTORE/createDeleteRequest (API 30+)"
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                    "MEDIASTORE/delete + RecoverableSecurityException (API 29)"
                else -> "MEDIASTORE/delete (API 28-)"
            }
            log(
                "plan | ${describe(uri)} | strategy=$branch | " +
                    "${describeSafPermission(uri)} | " +
                    describeMediaStoreLookup(uri),
            )
        }
        log(
            "routing | saf=${safUris.size} direct=${fileUris.size} " +
                "mediaStore=${mediaUris.size}",
        )

        for (uri in safUris) {
            deleteSafDocument(uri)
        }
        for (uri in fileUris) {
            deleteDirectFile(uri)
        }

        if (mediaUris.isEmpty()) {
            result.success(buildResponse(userCancelled = false))
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            requestBulkDelete(mediaUris, result)
            return
        }

        // Android 9 and below: ContentResolver.delete on shared media needs
        // WRITE_EXTERNAL_STORAGE, which is a runtime permission from API 23.
        // Without it the resolver throws
        //   SecurityException: requires android.permission.WRITE_EXTERNAL_STORAGE
        // Android 10+ never reaches here; it uses the delete request or SAF.
        if (needsLegacyWritePermission()) {
            log("legacy write permission missing, requesting before delete")
            requestLegacyWritePermission(mediaUris, result)
            return
        }

        runLegacyMediaDelete(mediaUris, result)
    }

    /**
     * The Android 10 and below deletion path, unchanged.
     *
     * Extracted so the API 28 permission-granted retry resumes through exactly
     * this code rather than a parallel copy.
     */
    private fun runLegacyMediaDelete(
        mediaUris: List<Uri>,
        result: MethodChannel.Result?,
    ) {
        // Try each, collecting anything recoverable.
        val recoverable = mutableListOf<IntentSender>()
        for (uri in mediaUris) {
            val sender = deleteMediaDirect(uri)
            if (sender != null) {
                recoverable += sender
            }
        }

        if (recoverable.isEmpty()) {
            result?.success(buildResponse(userCancelled = false))
            return
        }

        // Android 10 confirms one file at a time; surface the first prompt and
        // let the caller re-run for anything still present.
        pendingResult = result
        pendingUris = mediaUris
        if (!launchIntentSender(recoverable.first())) {
            pendingResult = null
            pendingUris = emptyList()
            result?.success(buildResponse(userCancelled = false))
        }
    }

    // ------------------------------------------------------------- deletion

    /**
     * True only for a genuine SAF document URI.
     *
     * `DocumentsContract.isDocumentUri` also answers true for MediaStore's
     * documents provider, so checking it alone routed ordinary MediaStore
     * rows down the SAF branch. `DocumentsContract.deleteDocument` then failed
     * on them, which the user saw as "Access to this file was denied" for
     * every media type.
     *
     * MediaStore URIs are excluded explicitly so they take the MediaStore
     * path, which is the one that can raise the system delete dialog.
     */
    private fun isSafDocument(uri: Uri): Boolean {
        if (uri.scheme != SCHEME_CONTENT) {
            return false
        }
        if (uri.authority == MediaStore.AUTHORITY) {
            return false
        }
        return try {
            DocumentsContract.isDocumentUri(context, uri)
        } catch (error: Exception) {
            false
        }
    }

    /**
     * True when this device needs a runtime `WRITE_EXTERNAL_STORAGE` grant
     * before shared media can be deleted, and does not yet have one.
     *
     * Only Android 9 (API 28) and below. The permission is capped at
     * `maxSdkVersion="28"` in the manifest and is meaningless on Android 10+,
     * where deletion goes through MediaStore delete requests or SAF.
     */
    private fun needsLegacyWritePermission(): Boolean {
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.P) {
            return false
        }
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
        log(
            "legacy write permission | sdkInt=${Build.VERSION.SDK_INT} " +
                "| granted=$granted",
        )
        return !granted
    }

    /** Asks for the legacy write permission, resuming the delete on the result. */
    private fun requestLegacyWritePermission(
        uris: List<Uri>,
        result: MethodChannel.Result,
    ) {
        val current = activity
        if (current == null) {
            log("legacy write permission | no activity, cannot request")
            for (uri in uris) {
                failedBeforePrompt += failure(uri, "Access to this file was denied.")
            }
            result.success(buildResponse(userCancelled = false))
            return
        }

        pendingResult = result
        pendingPermissionUris = uris
        current.requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQUEST_CODE_WRITE_PERMISSION,
        )
    }

    /**
     * Called from `MainActivity.onRequestPermissionsResult`.
     *
     * On grant, the delete resumes down the same legacy path. On denial the
     * items are kept and reported with the existing access-denied message.
     */
    fun handlePermissionResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_CODE_WRITE_PERMISSION) {
            return false
        }

        val result = pendingResult
        val uris = pendingPermissionUris
        pendingResult = null
        pendingPermissionUris = emptyList()

        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        log("legacy write permission result | granted=$granted")

        if (!granted) {
            // Denied: keep every file and report the existing failure.
            for (uri in uris) {
                failedBeforePrompt += failure(uri, "Access to this file was denied.")
            }
            result?.success(buildResponse(userCancelled = false))
            return true
        }

        // Granted: retry through the unchanged legacy path.
        runLegacyMediaDelete(uris, result)
        return true
    }

    /** True for a `file://` path this app may still delete directly. */
    private fun isDirectFile(uri: Uri): Boolean = uri.scheme == SCHEME_FILE

    private fun deleteSafDocument(uri: Uri) {
        log("SAF attempt | ${describe(uri)} | ${describeSafPermission(uri)}")
        try {
            val removed = DocumentsContract.deleteDocument(context.contentResolver, uri)
            log("SAF result | deleteDocument returned=$removed | uri=$uri")
            if (removed) {
                deletedBeforePrompt += uri.toString()
            } else {
                failedBeforePrompt += failure(uri, "Could not delete this file.")
            }
        } catch (error: SecurityException) {
            logError("SAF SecurityException | uri=$uri", error)
            failedBeforePrompt += failure(uri, "Access to this file was denied.")
        } catch (error: Exception) {
            logError("SAF Exception | uri=$uri", error)
            failedBeforePrompt += failure(uri, error.message ?: "Delete failed.")
        }
    }

    /**
     * Deletes a `file://` path directly.
     *
     * Only meaningful before scoped storage, or for files this app owns. It is
     * never used on a content URI: `File.delete()` on one silently fails and
     * would let the app report a success that never happened.
     */
    private fun deleteDirectFile(uri: Uri) {
        log("DIRECT attempt | ${describe(uri)}")
        val path = uri.path
        if (path.isNullOrEmpty()) {
            log("DIRECT abort | uri has no path | uri=$uri")
            failedBeforePrompt += failure(uri, "This file has no readable path.")
            return
        }

        val file = File(path)
        log(
            "DIRECT probe | path=$path | exists=${file.exists()} " +
                "| canRead=${file.canRead()} | canWrite=${file.canWrite()}",
        )
        if (!file.exists()) {
            // Already gone; treat as done rather than a failure.
            log("DIRECT result | already absent | path=$path")
            deletedBeforePrompt += uri.toString()
            return
        }

        val removed = try {
            file.delete()
        } catch (error: SecurityException) {
            logError("DIRECT SecurityException | path=$path", error)
            false
        }
        log("DIRECT result | File.delete returned=$removed | path=$path")

        if (removed) {
            deletedBeforePrompt += uri.toString()
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            failedBeforePrompt += failure(
                uri,
                "Android does not allow this app to delete this file.",
            )
        } else {
            failedBeforePrompt += failure(uri, "Could not delete this file.")
        }
    }

    /** Returns an [IntentSender] when the system needs the user to confirm. */
    private fun deleteMediaDirect(uri: Uri): IntentSender? {
        log(
            "MEDIASTORE attempt | ${describe(uri)} | " +
                describeMediaStoreLookup(uri),
        )
        return try {
            val rows = context.contentResolver.delete(uri, null, null)
            log("MEDIASTORE result | resolver.delete rows=$rows | uri=$uri")
            if (rows > 0) {
                deletedBeforePrompt += uri.toString()
            } else {
                failedBeforePrompt += failure(uri, "File was already gone.")
            }
            null
        } catch (error: SecurityException) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                error is RecoverableSecurityException
            ) {
                logError(
                    "MEDIASTORE RecoverableSecurityException, will prompt | " +
                        "uri=$uri",
                    error,
                )
                error.userAction.actionIntent.intentSender
            } else {
                logError(
                    "MEDIASTORE SecurityException, not recoverable | uri=$uri",
                    error,
                )
                failedBeforePrompt += failure(uri, "Access to this file was denied.")
                null
            }
        } catch (error: Exception) {
            logError("MEDIASTORE Exception | uri=$uri", error)
            failedBeforePrompt += failure(uri, error.message ?: "Delete failed.")
            null
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun requestBulkDelete(uris: List<Uri>, result: MethodChannel.Result) {
        val current = activity
        if (current == null) {
            result.error("NO_ACTIVITY", "No activity is attached.", null)
            return
        }

        log("MEDIASTORE bulk | createDeleteRequest for ${uris.size} uri(s)")
        for (uri in uris) {
            log("MEDIASTORE bulk item | ${describe(uri)}")
        }
        try {
            val pendingIntent = MediaStore.createDeleteRequest(
                context.contentResolver,
                uris,
            )
            pendingResult = result
            pendingUris = uris
            if (!launchIntentSender(pendingIntent.intentSender)) {
                log("MEDIASTORE bulk | launchIntentSender failed")
                pendingResult = null
                pendingUris = emptyList()
                result.error("DELETE_FAILED", "Could not show the delete dialog.", null)
            } else {
                log("MEDIASTORE bulk | system dialog shown, awaiting result")
            }
        } catch (error: Exception) {
            logError("MEDIASTORE bulk | createDeleteRequest threw", error)
            result.error("DELETE_FAILED", "Could not request deletion.", error.message)
        }
    }

    private fun launchIntentSender(sender: IntentSender): Boolean {
        val current = activity ?: return false
        return try {
            current.startIntentSenderForResult(sender, REQUEST_CODE_DELETE, null, 0, 0, 0)
            true
        } catch (error: IntentSender.SendIntentException) {
            false
        } catch (error: Exception) {
            false
        }
    }

    // -------------------------------------------------------------- results

    /** Called from `MainActivity.onActivityResult`. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_DELETE) {
            return false
        }
        val result = pendingResult
        val uris = pendingUris
        pendingResult = null
        pendingUris = emptyList()

        log(
            "system dialog result | resultCode=$resultCode " +
                "(RESULT_OK=${Activity.RESULT_OK}, " +
                "RESULT_CANCELED=${Activity.RESULT_CANCELED}) " +
                "| pendingUris=${uris.size}",
        )

        if (resultCode != Activity.RESULT_OK) {
            // The user declined the system dialog. Report honestly rather than
            // claiming success.
            log("system dialog | declined or cancelled, nothing deleted")
            result?.success(buildResponse(userCancelled = true))
            return true
        }

        // The system reports OK for the batch. Verify each row really went, so
        // the result screen never overstates what was removed.
        for (uri in uris) {
            val survived = stillExists(uri)
            log(
                "post-dialog verify | uri=$uri | stillExists=$survived | " +
                    describeMediaStoreLookup(uri),
            )
            if (survived) {
                failedBeforePrompt += failure(uri, "File could not be removed.")
            } else {
                deletedBeforePrompt += uri.toString()
            }
        }

        result?.success(buildResponse(userCancelled = false))
        return true
    }

    private fun stillExists(uri: Uri): Boolean {
        return try {
            context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null)
                ?.use { cursor -> cursor.count > 0 }
                ?: false
        } catch (error: Exception) {
            false
        }
    }

    private fun failure(uri: Uri, reason: String): Map<String, Any?> =
        mapOf("uri" to uri.toString(), "reason" to reason)

    private fun buildResponse(userCancelled: Boolean): Map<String, Any?> {
        log(
            "===== delete summary ===== " +
                "deleted=${deletedBeforePrompt.distinct().size} " +
                "| failed=${failedBeforePrompt.size} | cancelled=$userCancelled",
        )
        for (entry in failedBeforePrompt) {
            log("failure | uri=${entry["uri"]} | reason=${entry["reason"]}")
        }
        return mapOf(
            "deletedUris" to deletedBeforePrompt.distinct(),
            "failed" to failedBeforePrompt,
            "userCancelled" to userCancelled,
        )
    }

    private fun emptyResponse(): Map<String, Any?> = mapOf(
        "deletedUris" to emptyList<String>(),
        "failed" to emptyList<Map<String, Any?>>(),
        "userCancelled" to false,
    )
}
