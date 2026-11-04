package cn.fjob.todayagain.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands a verified APK from the app cache to the system package installer.
 *
 * Only files under cache/updates are accepted and they are shared through a
 * scoped FileProvider URI, so the channel cannot be used to install arbitrary
 * files.
 */
object UpdateInstallerPlugin {
    const val CHANNEL = "cn.fjob.todayagain/updates"

    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> result.success(canInstall(appContext))
                "openInstallPermissionSettings" -> {
                    openSettings(appContext)
                    result.success(true)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_args", "path is required", null)
                    } else {
                        install(appContext, path, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canInstall(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun install(context: Context, path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_apk", "downloaded APK not found", null)
            return
        }
        val canonical = file.canonicalFile
        val root = File(context.cacheDir, "updates").canonicalFile
        if (!canonical.path.startsWith(root.path + File.separator)) {
            result.error("invalid_path", "APK must live in cache/updates", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                canonical,
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            result.success(true)
        } catch (error: Exception) {
            result.error("install_failed", error.message, null)
        }
    }
}
