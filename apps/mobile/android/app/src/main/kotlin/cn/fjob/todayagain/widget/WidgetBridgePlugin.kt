package cn.fjob.todayagain.widget

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Bridge for `publishTimeline` and `clear` from Dart. */
object WidgetBridgePlugin {
    const val CHANNEL = "cn.fjob.todayagain/widgets"

    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "publishTimeline" -> {
                    val payload = call.argument<String>("json")
                    if (payload == null) {
                        result.error("bad_args", "json is required", null)
                        return@setMethodCallHandler
                    }
                    val accepted = SnapshotStore(appContext).storeTimeline(payload)
                    if (accepted) FjobWidgetProvider.updateAll(appContext)
                    result.success(accepted)
                }

                "clear" -> {
                    val payload = call.argument<String>("json")
                    if (payload == null) {
                        result.error("bad_args", "json is required", null)
                        return@setMethodCallHandler
                    }
                    val accepted = SnapshotStore(appContext).storeTombstone(payload)
                    if (accepted) FjobWidgetProvider.updateAll(appContext)
                    result.success(accepted)
                }

                else -> result.notImplemented()
            }
        }
    }

    /** Used only by unit tests and tooling. */
    fun handleForTest(context: Context, call: MethodCall): Any? = when (call.method) {
        "publishTimeline" -> SnapshotStore(context).storeTimeline(call.argument("json") ?: "")
        "clear" -> SnapshotStore(context).storeTombstone(call.argument("json") ?: "")
        else -> null
    }
}
