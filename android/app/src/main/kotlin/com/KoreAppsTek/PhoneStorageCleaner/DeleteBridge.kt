package com.KoreAppsTek.PhoneStorageCleaner

import android.Manifest
import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

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
class DeleteBridge(private val context: Context, private val progressChannel: MethodChannel? = null) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.KoreAppsTek.PhoneStorageCleaner/delete"
        const val REQUEST_CODE_DELETE = 4712
        const val REQUEST_CODE_WRITE_PERMISSION = 4713

        private const val SCHEME_CONTENT = "content"
        private const val SCHEME_FILE = "file"

        /** Diagnostics tag. Temporary; see docs/delete-debug-logging.md. */
        private const val DEBUG_TAG = "DELETE_DEBUG"
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val disposed = AtomicBoolean(false)
    @Volatile private var deleting = false
    private var ledger: DeleteProgressLedger? = null
    private var allUris: List<Uri> = emptyList()
    private val sizes = mutableMapOf<String, Long?>()
    private val existed = mutableMapOf<String, Boolean?>()
    private val eventLock = Any()
    private var latestEvent: Map<String, Any?>? = null
    private var eventPosted = false
    private fun report(event: Map<String, Any?>) {
        synchronized(eventLock) {
            latestEvent = event
            if (!eventPosted) {
                eventPosted = true
                main.post {
                    val latest = synchronized(eventLock) {
                        val value = latestEvent
                        latestEvent = null
                        eventPosted = false
                        value
                    }
                    if (!disposed.get() && latest != null) progressChannel?.invokeMethod("progress", latest)
                }
            }
        }
    }
    fun dispose() {
        disposed.set(true)
        activity = null
        val pending = pendingResult
        pendingResult = null
        pendingUris = emptyList()
        pendingPermissionUris = emptyList()
        deleteRequestCode = null
        permissionRequestCode = null
        if (pending != null) work(pending) {
            failPending(allUris, pending, "Android confirmation was interrupted; deletion was not confirmed.")
        }
        worker.shutdown()
    }
    private fun work(result: MethodChannel.Result?, action: () -> Unit) {
        try {
            worker.execute {
                try { action() }
                catch (_: Exception) { failPending(allUris, result, "Deletion could not be confirmed.") }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            failPending(allUris, result, "Cleanup is no longer available.")
        }
    }
    private fun beginItem(uri: Uri) {
        ledger?.update("deleting", uri.toString())
        if (!sizes.containsKey(uri.toString())) sizes[uri.toString()] = readSize(uri)
    }
    private fun readSize(uri: Uri): Long? = try {
        if (isDirectFile(uri)) {
            uri.path?.let { path -> File(path).takeIf { it.isFile }?.length() }
        } else {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (cursor.moveToFirst() && index >= 0 && !cursor.isNull(index))
                    cursor.getLong(index).takeIf { it >= 0 } else null
            }
        }
    } catch (_: Exception) { null }
    private fun removed(uri: Uri) {
        if (uri.toString() !in deletedBeforePrompt) deletedBeforePrompt += uri.toString()
        ledger?.settle(uri.toString(), "deleted", sizes[uri.toString()])
    }
    private fun skipped(uri: Uri) { ledger?.settle(uri.toString(), "skipped") }
    private fun reply(result: MethodChannel.Result?, cancelled: Boolean = false) {
        val response = buildResponse(cancelled)
        main.post { result?.success(response) }
    }
    private fun failPending(uris: List<Uri>, result: MethodChannel.Result?, reason: String) {
        for (uri in uris) if (ledger?.hasOutcome(uri.toString()) != true)
            failedBeforePrompt += failure(uri, reason)
        reply(result)
    }

    var activity: Activity? = null

    /** Set while a system dialog is showing. */
    private var pendingResult: MethodChannel.Result? = null
    private var deleteRequestCode: Int? = null
    private var permissionRequestCode: Int? = null

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
        if (disposed.get()) {
            result.error("UNAVAILABLE", "Cleanup is no longer available.", null)
            return
        }
        if (call.method != "deleteFiles") {
            result.notImplemented()
            return
        }

        val rawUris = call.argument<List<String>>("uris").orEmpty()
        if (rawUris.isEmpty()) {
            result.success(emptyResponse())
            return
        }
        if (deleting || pendingResult != null) {
            result.error("ALREADY_DELETING", "A delete is already in progress.", null)
            return
        }

        val uris = rawUris.distinct().mapNotNull { raw ->
            try {
                Uri.parse(raw)
            } catch (error: Exception) {
                null
            }
        }

        deleting = true
        allUris = uris
        sizes.clear(); existed.clear()
        ledger = DeleteProgressLedger(call.argument<String>("progressId"), uris.map { it.toString() }, ::report)
        ledger?.update("preparing")
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

        // Keep resolver/SAF/file IO off the platform thread so real settled
        // outcomes can render while the next item is processed.
        work(result) {
            for (uri in safUris) deleteSafDocument(uri)
            for (uri in fileUris) deleteDirectFile(uri)
            main.post {
                if (mediaUris.isEmpty()) {
                    reply(result)
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // The system dialog itself is still launched on main.
                    work(result) {
                        for (uri in mediaUris) {
                            beginItem(uri)
                            existed[uri.toString()] = stillExists(uri)
                        }
                        main.post { requestBulkDelete(mediaUris, result) }
                    }
                } else if (needsLegacyWritePermission()) {
                    requestLegacyWritePermission(mediaUris, result)
                } else work(result) { runLegacyMediaDelete(mediaUris, result) }
            }
        }
    }

    /**
     * Android 10 and below: the same authorization path, now observed on a worker.
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
            reply(result)
            return
        }

        // Android 10 confirms one file at a time; surface the first prompt and
        // let the caller re-run for anything still present.
        main.post {
            pendingResult = result
            pendingUris = mediaUris
            ledger?.update("awaitingConfirmation")
            if (!launchIntentSender(recoverable.first())) {
                pendingResult = null
                pendingUris = emptyList()
                failPending(mediaUris, result, "Could not show the delete dialog.")
            }
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
            reply(result)
            return
        }

        pendingResult = result
        pendingPermissionUris = uris
        ledger?.update("awaitingPermission")
        try {
            val code = DeleteProgressLedger.nextRequestCode()
            permissionRequestCode = code
            current.requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                code,
            )
        } catch (_: Exception) {
            pendingResult = null
            pendingPermissionUris = emptyList()
            permissionRequestCode = null
            failPending(uris, result, "Could not request permission.")
        }
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
        if (requestCode != permissionRequestCode) {
            return false
        }

        permissionRequestCode = null
        val result = pendingResult ?: return true
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
            reply(result)
            return true
        }

        // Granted: retry through the unchanged legacy path.
        work(result) { runLegacyMediaDelete(uris, result) }
        return true
    }

    /** True for a `file://` path this app may still delete directly. */
    private fun isDirectFile(uri: Uri): Boolean = uri.scheme == SCHEME_FILE

    private fun deleteSafDocument(uri: Uri) {
        beginItem(uri)
        log("SAF attempt | ${describe(uri)} | ${describeSafPermission(uri)}")
        try {
            val removed = DocumentsContract.deleteDocument(context.contentResolver, uri)
            log("SAF result | deleteDocument returned=$removed | uri=$uri")
            if (removed) {
                removed(uri)
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
        beginItem(uri)
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
            // Already absent is skipped, never newly reclaimed storage.
            log("DIRECT result | already absent | path=$path")
            skipped(uri)
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
            removed(uri)
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
        beginItem(uri)
        existed[uri.toString()] = stillExists(uri)
        log(
            "MEDIASTORE attempt | ${describe(uri)} | " +
                describeMediaStoreLookup(uri),
        )
        return try {
            val rows = context.contentResolver.delete(uri, null, null)
            log("MEDIASTORE result | resolver.delete rows=$rows | uri=$uri")
            if (DeleteProgressLedger.directRows(rows) == "deleted") removed(uri) else skipped(uri)
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
            failPending(uris, result, "No activity is attached.")
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
            ledger?.update("awaitingConfirmation")
            if (!launchIntentSender(pendingIntent.intentSender)) {
                log("MEDIASTORE bulk | launchIntentSender failed")
                pendingResult = null
                pendingUris = emptyList()
                failPending(uris, result, "Could not show the delete dialog.")
            } else {
                log("MEDIASTORE bulk | system dialog shown, awaiting result")
            }
        } catch (error: Exception) {
            logError("MEDIASTORE bulk | createDeleteRequest threw", error)
            failPending(uris, result, "Could not request deletion.")
        }
    }

    private fun launchIntentSender(sender: IntentSender): Boolean {
        val current = activity ?: return false
        return try {
            val code = DeleteProgressLedger.nextRequestCode()
            deleteRequestCode = code
            current.startIntentSenderForResult(sender, code, null, 0, 0, 0)
            true
        } catch (error: IntentSender.SendIntentException) {
            deleteRequestCode = null
            false
        } catch (error: Exception) {
            deleteRequestCode = null
            false
        }
    }

    // -------------------------------------------------------------- results

    /** Called from `MainActivity.onActivityResult`. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != deleteRequestCode) {
            return false
        }
        deleteRequestCode = null
        val result = pendingResult ?: return true
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
            reply(result, cancelled = true)
            return true
        }

        // Consent is not evidence of deletion. Verify in a worker, preserving
        // unavailable queries as unknown rather than claiming the file is gone.
        work(result) {
            for (uri in uris) {
                if (ledger?.hasOutcome(uri.toString()) == true) continue
                ledger?.update("verifying", uri.toString())
                when (DeleteProgressLedger.afterConfirmation(existed[uri.toString()], stillExists(uri))) {
                    "deleted" -> removed(uri)
                    "skipped" -> skipped(uri)
                    else -> failedBeforePrompt += failure(uri, "Deletion could not be confirmed.")
                }
            }
            reply(result)
        }
        return true
    }

    /** null means verification unavailable, not absent. */
    private fun stillExists(uri: Uri): Boolean? = try {
        context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), null, null, null)
            ?.use { cursor -> cursor.count > 0 }
    } catch (_: Exception) { null }

    private fun failure(uri: Uri, reason: String): Map<String, Any?> {
        ledger?.settle(uri.toString(), "failed")
        return mapOf("uri" to uri.toString(), "reason" to reason)
    }

    private fun buildResponse(userCancelled: Boolean): Map<String, Any?> {
        if (!userCancelled) for (uri in allUris) {
            if (ledger?.hasOutcome(uri.toString()) != true)
                failedBeforePrompt += failure(uri, "Deletion was not confirmed.")
        }
        log(
            "===== delete summary ===== " +
                "deleted=${deletedBeforePrompt.distinct().size} " +
                "| failed=${failedBeforePrompt.size} | cancelled=$userCancelled",
        )
        for (entry in failedBeforePrompt) {
            log("failure | uri=${entry["uri"]} | reason=${entry["reason"]}")
        }
        ledger?.finish(userCancelled)
        deleting = false
        return mapOf(
            "accountingVersion" to 1,
            "confirmedBytesByUri" to ledger?.byteSizes().orEmpty(),
            "skippedUris" to ledger?.skipped().orEmpty(),
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
