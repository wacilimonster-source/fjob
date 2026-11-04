package cn.fjob.todayagain

import android.content.Intent
import android.os.Bundle
import cn.fjob.todayagain.update.UpdateInstallerPlugin
import cn.fjob.todayagain.widget.WidgetBridgePlugin
import cn.fjob.todayagain.widget.WidgetUpdateWorker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var initialLink: String? = null
    private var linkSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        initialLink = intent?.dataString?.takeIf { it.startsWith("fjob://") }
        super.onCreate(savedInstanceState)
        WidgetUpdateWorker.schedule(applicationContext)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        WidgetBridgePlugin.register(messenger, applicationContext)
        UpdateInstallerPlugin.register(messenger, applicationContext)

        MethodChannel(messenger, DEEP_LINK_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialDeepLink") {
                result.success(initialLink)
                initialLink = null
            } else {
                result.notImplemented()
            }
        }

        EventChannel(messenger, DEEP_LINK_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    linkSink = events
                    val pending = initialLink
                    if (pending != null) {
                        events?.success(pending)
                        initialLink = null
                    }
                }

                override fun onCancel(arguments: Any?) {
                    linkSink = null
                }
            },
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString
        if (link != null && link.startsWith("fjob://")) {
            linkSink?.success(link)
        }
    }

    companion object {
        private const val DEEP_LINK_CHANNEL = "cn.fjob.todayagain/deeplinks"
        private const val DEEP_LINK_EVENTS = "cn.fjob.todayagain/deeplinks/events"
    }
}
