package cn.fjob.todayagain.files

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Saves an exported .fjob bundle without the Storage Access Framework picker.
 *
 * Some OEM file pickers fail to return a writable document, so the Dart export
 * flow keeps a fallback that writes straight into the public Downloads folder
 * on Android 10+ (MediaStore, no permission) or the app-specific external
 * Downloads folder on Android 8/9.
 */
object LedgerFilesPlugin {
    const val CHANNEL = "cn.fjob.todayagain/files"

    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val fileName = call.argument<String>("fileName")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (fileName.isNullOrBlank() || bytes == null) {
                        result.error("bad_args", "fileName and bytes are required", null)
                    } else {
                        // Writing can take a moment for a large ledger; keep the
                        // platform thread responsive and answer there.
                        Thread {
                            try {
                                val path = save(
                                    appContext,
                                    sanitizeFileName(fileName),
                                    bytes,
                                )
                                Handler(Looper.getMainLooper()).post {
                                    result.success(path)
                                }
                            } catch (error: Exception) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error(
                                        "save_failed",
                                        error.message ?: "unable to save file",
                                        null,
                                    )
                                }
                            }
                        }.start()
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    /// File names come from the Dart export flow, but keep path traversal and
    /// reserved characters out of the public Downloads folder anyway.
    fun sanitizeFileName(name: String): String {
        val cleaned = name
            .replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001F]"), "_")
            .trim()
        return (if (cleaned.isEmpty()) "fjob-export.fjob" else cleaned).take(120)
    }

    private fun save(context: Context, name: String, bytes: ByteArray): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return saveToPublicDownloads(context, name, bytes)
        }
        val base = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: context.filesDir
        val target = File(File(base, "FJOB"), name)
        target.parentFile?.mkdirs()
        target.writeBytes(bytes)
        return target.absolutePath
    }

    private fun saveToPublicDownloads(
        context: Context,
        name: String,
        bytes: ByteArray,
    ): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/octet-stream")
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/FJOB",
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("无法创建下载文件")
        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("无法写入下载文件")
            val ready = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, ready, null, null)
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
        return "${Environment.DIRECTORY_DOWNLOADS}/FJOB/$name"
    }
}
