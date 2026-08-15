package com.mobilecleaner.app

import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val STORAGE_CHANNEL = "com.mobilecleaner.app/storage"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "getStorageInfo") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                try {
                    val fileSystem = StatFs(Environment.getDataDirectory().absolutePath)
                    val blockSize = fileSystem.blockSizeLong
                    val totalBytes = fileSystem.blockCountLong * blockSize
                    val freeBytes = fileSystem.availableBlocksLong * blockSize

                    result.success(
                        mapOf(
                            "totalBytes" to totalBytes,
                            "freeBytes" to freeBytes,
                        ),
                    )
                } catch (error: Exception) {
                    result.error(
                        "STORAGE_UNAVAILABLE",
                        "Unable to read device storage.",
                        error.message,
                    )
                }
            }
    }
}
