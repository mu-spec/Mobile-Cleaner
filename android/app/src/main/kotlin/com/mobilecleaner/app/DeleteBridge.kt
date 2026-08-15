package com.mobilecleaner.app

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

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

        private const val SCHEME_CONTENT = "content"
    }

    var activity: Activity? = null

    /** Set while a system dialog is showing. */
    private var pendingResult: MethodChannel.Result? = null

    /** URIs awaiting the outcome of the current system dialog. */
    private var pendingUris: List<Uri> = emptyList()

    /** Files already removed before the dialog was raised. */
    private var deletedBeforePrompt: MutableList<String> = mutableListOf()

    private var failedBeforePrompt: MutableList<Map<String, Any?>> = mutableListOf()

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

        // SAF documents never need the MediaStore dialog.
        val safUris = uris.filter { isSafDocument(it) }
        val mediaUris = uris.filter { !isSafDocument(it) }

        for (uri in safUris) {
            deleteSafDocument(uri)
        }

        if (mediaUris.isEmpty()) {
            result.success(buildResponse(userCancelled = false))
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            requestBulkDelete(mediaUris, result)
            return
        }

        // Android 10 and below: try each, collecting anything recoverable.
        val recoverable = mutableListOf<IntentSender>()
        for (uri in mediaUris) {
            val sender = deleteMediaDirect(uri)
            if (sender != null) {
                recoverable += sender
            }
        }

        if (recoverable.isEmpty()) {
            result.success(buildResponse(userCancelled = false))
            return
        }

        // Android 10 confirms one file at a time; surface the first prompt and
        // let the caller re-run for anything still present.
        pendingResult = result
        pendingUris = mediaUris
        if (!launchIntentSender(recoverable.first())) {
            pendingResult = null
            pendingUris = emptyList()
            result.success(buildResponse(userCancelled = false))
        }
    }

    // ------------------------------------------------------------- deletion

    private fun isSafDocument(uri: Uri): Boolean {
        return uri.scheme == SCHEME_CONTENT && DocumentsContract.isDocumentUri(context, uri)
    }

    private fun deleteSafDocument(uri: Uri) {
        try {
            val removed = DocumentsContract.deleteDocument(context.contentResolver, uri)
            if (removed) {
                deletedBeforePrompt += uri.toString()
            } else {
                failedBeforePrompt += failure(uri, "Could not delete this file.")
            }
        } catch (error: SecurityException) {
            failedBeforePrompt += failure(uri, "Access to this file was denied.")
        } catch (error: Exception) {
            failedBeforePrompt += failure(uri, error.message ?: "Delete failed.")
        }
    }

    /** Returns an [IntentSender] when the system needs the user to confirm. */
    private fun deleteMediaDirect(uri: Uri): IntentSender? {
        return try {
            val rows = context.contentResolver.delete(uri, null, null)
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
                error.userAction.actionIntent.intentSender
            } else {
                failedBeforePrompt += failure(uri, "Access to this file was denied.")
                null
            }
        } catch (error: Exception) {
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

        try {
            val pendingIntent = MediaStore.createDeleteRequest(
                context.contentResolver,
                uris,
            )
            pendingResult = result
            pendingUris = uris
            if (!launchIntentSender(pendingIntent.intentSender)) {
                pendingResult = null
                pendingUris = emptyList()
                result.error("DELETE_FAILED", "Could not show the delete dialog.", null)
            }
        } catch (error: Exception) {
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

        if (resultCode != Activity.RESULT_OK) {
            // The user declined the system dialog. Report honestly rather than
            // claiming success.
            result?.success(buildResponse(userCancelled = true))
            return true
        }

        // The system reports OK for the batch. Verify each row really went, so
        // the result screen never overstates what was removed.
        for (uri in uris) {
            if (stillExists(uri)) {
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

    private fun buildResponse(userCancelled: Boolean): Map<String, Any?> = mapOf(
        "deletedUris" to deletedBeforePrompt.distinct(),
        "failed" to failedBeforePrompt,
        "userCancelled" to userCancelled,
    )

    private fun emptyResponse(): Map<String, Any?> = mapOf(
        "deletedUris" to emptyList<String>(),
        "failed" to emptyList<Map<String, Any?>>(),
        "userCancelled" to false,
    )
}
