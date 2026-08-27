package com.mobilecleaner.app

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.storage.StorageManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Reads installed applications, as far as Android permits.
 *
 * ## What Android permits, and what this deliberately does not do
 *
 * Since Android 11 an app cannot see the full package list by default.
 * `QUERY_ALL_PACKAGES` would lift that, but it is a Play-restricted permission
 * requiring case-by-case approval and is **not** used here. Instead the
 * manifest declares a `<queries>` entry for the LAUNCHER intent, which reveals
 * exactly the apps a person would recognise as "my apps" — those with a
 * launcher icon. Background services, system components with no icon, and
 * other apps' internals stay invisible, which is the correct answer rather
 * than a limitation to work around.
 *
 * Consequence to be honest about in the UI: the list is *launchable apps*, not
 * every installed package. It will not match the count in system Settings.
 *
 * ## Size information is tiered
 *
 * | Tier | Source | Needs |
 * |---|---|---|
 * | APK size | `sourceDir` file length + split APKs | nothing |
 * | App + data + cache | `StorageStatsManager` | `PACKAGE_USAGE_STATS`, API 26+ |
 *
 * The APK size is always available and is reported for every app. The full
 * footprint needs Usage Access, which the user grants in system Settings — it
 * cannot be requested with a runtime dialog. Until then the app reports the
 * APK size and says so, rather than showing a wrong total or a blank.
 *
 * ## This bridge never uninstalls anything itself
 *
 * [uninstallApp] fires the platform's own uninstall dialog. The decision, the
 * confirmation, and the deletion all belong to Android. Nothing here removes
 * an app, and there is no silent path that could.
 */
class InstalledAppsBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mobilecleaner.app/installed_apps"

        /** Icons are rendered at this size before being sent to Dart. */
        private const val ICON_SIZE = 96

        private const val ICON_QUALITY = 90

        private const val TAG = "InstalledAppsBridge"
    }

    /** Set by [MainActivity]; null once the activity goes away. */
    var activity: Activity? = null

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInstalledApps" -> getInstalledApps(call, result)
            "hasUsageAccess" -> result.success(hasUsageAccess())
            "openUsageAccessSettings" -> result.success(openUsageAccessSettings())
            "openApp" -> result.success(openApp(call.argument<String>("package")))
            "openAppSettings" -> result.success(
                openAppSettings(call.argument<String>("package")),
            )
            "uninstallApp" -> result.success(
                uninstallApp(call.argument<String>("package")),
            )
            "isInstalled" -> result.success(
                isInstalled(call.argument<String>("package")),
            )
            else -> result.notImplemented()
        }
    }

    private fun getInstalledApps(call: MethodCall, result: MethodChannel.Result) {
        val includeIcons = call.argument<Boolean>("includeIcons") ?: true

        try {
            executor.execute {
                val apps = try {
                    readApps(includeIcons)
                } catch (error: Throwable) {
                    // OutOfMemoryError is conceivable while rasterising icons.
                    emptyList()
                }
                mainHandler.post {
                    result.success(
                        mapOf(
                            "apps" to apps,
                            "hasUsageAccess" to hasUsageAccess(),
                            // Below API 26 there is no StorageStatsManager at
                            // all, so Usage Access would not help either.
                            "sizeDetailSupported" to
                                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O),
                        ),
                    )
                }
            }
        } catch (rejected: RejectedExecutionException) {
            result.success(
                mapOf(
                    "apps" to emptyList<Map<String, Any?>>(),
                    "hasUsageAccess" to false,
                    "sizeDetailSupported" to false,
                ),
            )
        }
    }

    private fun readApps(includeIcons: Boolean): List<Map<String, Any?>> {
        val packageManager = context.getPackageManager()

        // Only apps with a launcher entry. This is the `<queries>` contract:
        // asking for anything broader would return nothing useful anyway.
        val launcherIntent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = packageManager.queryIntentActivities(launcherIntent, 0)

        val statsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            hasUsageAccess()
        ) {
            context.getSystemService(Context.STORAGE_STATS_SERVICE)
                as? StorageStatsManager
        } else {
            null
        }

        val seen = mutableSetOf<String>()
        val apps = mutableListOf<Map<String, Any?>>()

        for (info in resolved) {
            val packageName = info.activityInfo?.packageName ?: continue
            if (packageName == context.getPackageName()) {
                // Listing ourselves and offering an Uninstall button would be
                // a trap, not a feature.
                continue
            }
            if (!seen.add(packageName)) {
                // An app can declare several launcher activities.
                continue
            }

            val appInfo: ApplicationInfo = try {
                packageManager.getApplicationInfo(packageName, 0)
            } catch (missing: PackageManager.NameNotFoundException) {
                continue
            }

            val apkBytes = apkSizeOf(appInfo)
            var appBytes: Long? = null
            var dataBytes: Long? = null
            var cacheBytes: Long? = null

            if (statsManager != null) {
                try {
                    val stats = statsManager.queryStatsForPackage(
                        StorageManager.UUID_DEFAULT,
                        packageName,
                        Process.myUserHandle(),
                    )
                    appBytes = stats.getAppBytes()
                    dataBytes = stats.getDataBytes()
                    cacheBytes = stats.getCacheBytes()
                } catch (error: Exception) {
                    // Left null: an unmeasurable app reports its APK size only
                    // rather than a fabricated total.
                }
            }

            val packageInfo = try {
                packageManager.getPackageInfo(packageName, 0)
            } catch (missing: PackageManager.NameNotFoundException) {
                null
            }
            val installedAt = packageInfo?.firstInstallTime ?: 0L
            val updatedAt = packageInfo?.lastUpdateTime ?: 0L
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo?.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageInfo?.versionCode?.toLong()
            }

            apps += mapOf(
                "packageName" to packageName,
                "name" to appInfo.loadLabel(packageManager).toString(),
                "apkBytes" to apkBytes,
                "appBytes" to appBytes,
                "dataBytes" to dataBytes,
                "cacheBytes" to cacheBytes,
                "isSystemApp" to isSystemApp(appInfo),
                "versionName" to packageInfo?.versionName,
                "versionCode" to versionCode,
                "installedAtMillis" to installedAt,
                "updatedAtMillis" to updatedAt,
                // A launcher intent is how Open works, so record whether one
                // exists rather than letting the button fail later.
                "canOpen" to
                    (packageManager.getLaunchIntentForPackage(packageName) != null),
                "icon" to if (includeIcons) {
                    iconBytes(appInfo, packageManager)
                } else {
                    null
                },
            )
        }

        return apps
    }

    /**
     * Bytes the installed package occupies on disk.
     *
     * Split APKs are included: a modern app ships a base plus per-density and
     * per-ABI splits, and counting only the base would understate it badly.
     */
    private fun apkSizeOf(info: ApplicationInfo): Long {
        var total = 0L
        val paths = mutableListOf<String>()
        info.sourceDir?.let { paths += it }
        info.splitSourceDirs?.let { paths.addAll(it.filterNotNull()) }

        for (path in paths.distinct()) {
            total += try {
                val file = File(path)
                if (file.isFile()) file.length() else 0L
            } catch (error: SecurityException) {
                0L
            }
        }
        return total
    }

    private fun isSystemApp(info: ApplicationInfo): Boolean {
        val system = info.flags and ApplicationInfo.FLAG_SYSTEM != 0
        val updatedSystem =
            info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP != 0
        return system || updatedSystem
    }

    /** Rasterises the launcher icon to a small PNG, or null on failure. */
    private fun iconBytes(
        info: ApplicationInfo,
        packageManager: PackageManager,
    ): ByteArray? {
        return try {
            val drawable: Drawable = info.loadIcon(packageManager)
            val bitmap = drawableToBitmap(drawable) ?: return null
            try {
                ByteArrayOutputStream().use { stream ->
                    bitmap.compress(Bitmap.CompressFormat.PNG, ICON_QUALITY, stream)
                    stream.toByteArray()
                }
            } finally {
                bitmap.recycle()
            }
        } catch (error: Throwable) {
            null
        }
    }

    /**
     * Draws any drawable into a bitmap.
     *
     * Adaptive icons are not [BitmapDrawable]s and have no intrinsic bitmap,
     * so they must be drawn through a [Canvas] rather than cast.
     */
    private fun drawableToBitmap(drawable: Drawable): Bitmap? {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return Bitmap.createScaledBitmap(
                drawable.bitmap,
                ICON_SIZE,
                ICON_SIZE,
                true,
            )
        }

        val bitmap = Bitmap.createBitmap(
            ICON_SIZE,
            ICON_SIZE,
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.getWidth(), canvas.getHeight())
        drawable.draw(canvas)
        return bitmap
    }

    /**
     * Whether the user has granted Usage Access.
     *
     * Checked through [AppOpsManager] rather than `checkSelfPermission`,
     * because `PACKAGE_USAGE_STATS` is an appop-backed special access that a
     * plain permission check reports incorrectly.
     */
    private fun hasUsageAccess(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE)
                as? AppOpsManager ?: return false
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    context.getPackageName(),
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    context.getPackageName(),
                )
            }
            if (mode == AppOpsManager.MODE_DEFAULT) {
                context.checkCallingOrSelfPermission(
                    android.Manifest.permission.PACKAGE_USAGE_STATS,
                ) == PackageManager.PERMISSION_GRANTED
            } else {
                mode == AppOpsManager.MODE_ALLOWED
            }
        } catch (error: Exception) {
            false
        }
    }

    /** Opens the system Usage Access screen. There is no runtime dialog. */
    private fun openUsageAccessSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            launch(intent)
        } catch (error: Exception) {
            false
        }
    }

    private fun openApp(packageName: String?): Boolean {
        if (packageName.isNullOrEmpty()) {
            return false
        }
        return try {
            val intent = context.getPackageManager()
                .getLaunchIntentForPackage(packageName) ?: return false
            launch(intent)
        } catch (error: Exception) {
            false
        }
    }

    private fun openAppSettings(packageName: String?): Boolean {
        if (packageName.isNullOrEmpty()) {
            return false
        }
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
            launch(intent)
        } catch (error: Exception) {
            false
        }
    }

    /**
     * Asks Android to uninstall an app.
     *
     * `ACTION_DELETE` shows the platform's own confirmation. This app neither
     * removes the package nor sees the answer directly; the list is refreshed
     * when the screen resumes, so a cancelled uninstall simply leaves the app
     * in place.
     */
    private fun uninstallApp(packageName: String?): Boolean {
        if (packageName.isNullOrEmpty()) {
            return false
        }
        if (packageName == context.getPackageName()) {
            return false
        }
        return try {
            val intent = Intent(Intent.ACTION_DELETE)
                .setData(Uri.fromParts("package", packageName, null))
            launch(intent)
        } catch (error: Exception) {
            false
        }
    }

    /** True when the package is still present. Used to confirm an uninstall. */
    private fun isInstalled(packageName: String?): Boolean {
        if (packageName.isNullOrEmpty()) {
            return false
        }
        return try {
            context.getPackageManager().getApplicationInfo(packageName, 0)
            true
        } catch (missing: PackageManager.NameNotFoundException) {
            false
        } catch (error: Exception) {
            false
        }
    }

    /**
     * Starts an intent from the activity when possible.
     *
     * Falls back to the application context with `NEW_TASK`, which is required
     * when no activity is attached and would throw otherwise.
     */
    private fun launch(intent: Intent): Boolean {
        val host = activity
        return try {
            if (host != null) {
                host.startActivity(intent)
            } else {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
            }
            true
        } catch (error: Exception) {
            // No handling activity, or the device blocks it. Logged rather
            // than swallowed silently: a dead-looking button with no trace in
            // logcat is exactly what made the missing REQUEST_DELETE_PACKAGES
            // permission so hard to spot.
            Log.w(TAG, "Could not start ${intent.action}: ${error.message}")
            false
        }
    }

    fun dispose() {
        executor.shutdown()
    }
}
