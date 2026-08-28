package com.mobilecleaner.app

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Opens Android's chooser so the user can pick WhatsApp or any share app. */
class ShareBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.mobilecleaner.app/share"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "shareText") {
            result.notImplemented()
            return
        }

        val text = call.argument<String>("text")?.trim().orEmpty()
        if (text.isEmpty()) {
            result.error("EMPTY_SHARE", "There is no cleanup result to share.", null)
            return
        }

        val subject = call.argument<String>("subject")?.trim().orEmpty()
        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            if (subject.isNotEmpty()) {
                putExtra(Intent.EXTRA_SUBJECT, subject)
            }
        }
        val chooser = Intent.createChooser(sendIntent, "Share cleanup result").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            context.startActivity(chooser)
            result.success(true)
        } catch (error: Exception) {
            result.error("SHARE_UNAVAILABLE", "No sharing app is available.", error.message)
        }
    }
}
