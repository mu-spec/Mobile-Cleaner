package com.KoreAppsTek.PhoneStorageCleaner

import android.content.Intent
import android.os.Environment
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val STORAGE_CHANNEL = "com.KoreAppsTek.PhoneStorageCleaner/storage"
    }

    private var scanProgress: ScanProgressBridge? = null
    private var fileScanner: FileScannerBridge? = null
    private var thumbnailLoader: ThumbnailLoader? = null
    private var safAccess: SafAccessBridge? = null
    private var deleteBridge: DeleteBridge? = null
    private var hashBridge: FileHashBridge? = null
    private var perceptualHashBridge: PerceptualHashBridge? = null
    private var photoQualityBridge: PhotoQualityBridge? = null
    private var installedAppsBridge: InstalledAppsBridge? = null

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ShareBridge.CHANNEL,
        ).setMethodCallHandler(ShareBridge(applicationContext))

        val progress = ScanProgressBridge(flutterEngine.dartExecutor.binaryMessenger)
        scanProgress = progress
        val saf = SafAccessBridge(applicationContext)
        saf.activity = this
        safAccess = saf
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SafAccessBridge.CHANNEL,
        ).setMethodCallHandler(saf)

        val scanner = FileScannerBridge(applicationContext, saf, progress)
        fileScanner = scanner
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FileScannerBridge.CHANNEL,
        ).setMethodCallHandler(scanner)

        val deleter = DeleteBridge(applicationContext, MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.KoreAppsTek.PhoneStorageCleaner/delete_progress",
        ))
        deleter.activity = this
        deleteBridge = deleter
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DeleteBridge.CHANNEL,
        ).setMethodCallHandler(deleter)

        val hasher = FileHashBridge(applicationContext, progress)
        hashBridge = hasher
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FileHashBridge.CHANNEL,
        ).setMethodCallHandler(hasher)

        val perceptual = PerceptualHashBridge(applicationContext, progress)
        perceptualHashBridge = perceptual
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PerceptualHashBridge.CHANNEL,
        ).setMethodCallHandler(perceptual)

        val quality = PhotoQualityBridge(applicationContext, progress)
        photoQualityBridge = quality
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PhotoQualityBridge.CHANNEL,
        ).setMethodCallHandler(quality)

        val installedApps = InstalledAppsBridge(applicationContext, progress)
        installedApps.activity = this
        installedAppsBridge = installedApps
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            InstalledAppsBridge.CHANNEL,
        ).setMethodCallHandler(installedApps)

        val loader = ThumbnailLoader(applicationContext)
        thumbnailLoader = loader
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ThumbnailLoader.CHANNEL,
        ).setMethodCallHandler(loader)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        // The API 28 write-permission request that gates legacy deletion.
        if (deleteBridge?.handlePermissionResult(requestCode, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (safAccess?.handleActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        if (deleteBridge?.handleActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        scanProgress?.dispose()
        scanProgress = null
        fileScanner?.dispose()
        fileScanner = null
        thumbnailLoader?.dispose()
        thumbnailLoader = null
        safAccess?.activity = null
        safAccess = null
        deleteBridge?.activity = null
        deleteBridge?.dispose()
        deleteBridge = null
        hashBridge?.dispose()
        hashBridge = null
        perceptualHashBridge?.dispose()
        perceptualHashBridge = null
        photoQualityBridge?.dispose()
        photoQualityBridge = null
        installedAppsBridge?.activity = null
        installedAppsBridge?.dispose()
        installedAppsBridge = null
        super.onDestroy()
    }
}
