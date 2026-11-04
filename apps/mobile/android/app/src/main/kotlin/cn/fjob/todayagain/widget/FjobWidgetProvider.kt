package cn.fjob.todayagain.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.RemoteViews
import cn.fjob.todayagain.MainActivity
import cn.fjob.todayagain.R
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * RemoteViews renderer. It only picks the newest pre-computed entry that is
 * already in the past; no wage, expense or P&L arithmetic happens here.
 */
class FjobWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { id -> update(context, appWidgetManager, id) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        update(context, appWidgetManager, appWidgetId)
    }

    override fun onEnabled(context: Context) {
        WidgetUpdateWorker.schedule(context)
    }

    override fun onDisabled(context: Context) {
        WidgetUpdateWorker.cancel(context)
    }

    companion object {
        private val TIME_FORMAT = DateTimeFormatter.ofPattern("HH:mm")

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, FjobWidgetProvider::class.java),
            )
            ids.forEach { id -> update(context, manager, id) }
        }

        private fun update(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val store = SnapshotStore(context)
            val size = sizeFor(manager.getAppWidgetOptions(widgetId))
            val snapshot = resolve(store)
            val views = RemoteViews(context.packageName, size.layout)
            bind(context, views, size, snapshot, store)
            manager.updateAppWidget(widgetId, views)
        }

        private fun resolve(store: SnapshotStore): WidgetSnapshot? {
            store.loadTombstone()?.let { return it }
            val timeline = store.loadTimeline() ?: return null
            return timeline.entryFor(System.currentTimeMillis())
        }

        private enum class Size(
            val layout: Int,
            val hasSplit: Boolean,
            val hasArt: Boolean,
        ) {
            SMALL(R.layout.widget_small, hasSplit = false, hasArt = false),
            MEDIUM(R.layout.widget_medium, hasSplit = true, hasArt = false),
            LARGE(R.layout.widget_large, hasSplit = true, hasArt = true),
        }

        private fun sizeFor(options: Bundle): Size {
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            return when {
                minWidth >= 290 -> Size.LARGE
                minWidth >= 160 -> Size.MEDIUM
                else -> Size.SMALL
            }
        }

        private fun bind(
            context: Context,
            views: RemoteViews,
            size: Size,
            snapshot: WidgetSnapshot?,
            store: SnapshotStore,
        ) {
            val privacy = snapshot?.privacy == true
            val tombstone = snapshot?.tombstone == true
            val stale = snapshot != null && !tombstone &&
                System.currentTimeMillis() > snapshot.validUntil

            views.setTextViewText(R.id.widget_title, "今日又白干")
            views.setTextViewText(R.id.widget_face, faceFor(snapshot))
            views.setTextViewText(R.id.widget_total, totalText(snapshot))
            if (size != Size.SMALL) {
                // The small layout has no caption row.
                views.setTextViewText(
                    R.id.widget_caption,
                    when {
                        snapshot == null -> "打开 App 完成登记"
                        tombstone -> "账本已清空，待重新配置"
                        else -> snapshot.caption
                    },
                )
            }
            views.setTextViewText(R.id.widget_time, timeText(snapshot, stale))

            if (size.hasSplit) {
                views.setTextViewText(R.id.widget_wage, amountText(snapshot?.wage, privacy))
                views.setTextViewText(
                    R.id.widget_stock,
                    amountText(snapshot?.stockDaily, privacy),
                )
                views.setTextViewText(
                    R.id.widget_housing,
                    amountText(snapshot?.housing, privacy),
                )
            }
            if (size.hasArt) {
                views.setTextViewText(
                    R.id.widget_gold,
                    amountText(snapshot?.goldDaily, privacy),
                )
                views.setTextViewText(
                    R.id.widget_car,
                    amountText(snapshot?.car, privacy),
                )
                val housingLabel = when (snapshot?.housingMode) {
                    "rent" -> "房租"
                    "mortgage" -> "房贷"
                    else -> "住房"
                }
                views.setTextViewText(R.id.widget_housing_label, housingLabel)
            }

            val description = when {
                snapshot == null -> "今日又白干，打开 App 完成登记"
                privacy -> "今日又白干，金额已隐藏"
                tombstone -> "今日又白干，账本已清空"
                else -> "今日又白干，${snapshot.caption}"
            }
            views.setContentDescription(R.id.widget_root, description)

            views.setOnClickPendingIntent(R.id.widget_root, openApp(context, "fjob://dashboard", 1))
            if (size.hasSplit) {
                views.setOnClickPendingIntent(
                    R.id.widget_housing_cell,
                    openApp(context, "fjob://expenses/housing", 2),
                )
                views.setOnClickPendingIntent(
                    R.id.widget_refresh,
                    openApp(context, "fjob://widgets", 3),
                )
            }
            if (size.hasArt) {
                views.setOnClickPendingIntent(
                    R.id.widget_car_cell,
                    openApp(context, "fjob://expenses/car", 4),
                )
            }
        }

        private fun faceFor(snapshot: WidgetSnapshot?): String = when {
            snapshot == null -> "(・_・)"
            snapshot.privacy -> "(－_－)"
            snapshot.isNegative -> "(－_－)"
            else -> "( ˘ᴗ˘ )"
        }

        private fun totalText(snapshot: WidgetSnapshot?): String {
            if (snapshot == null) return "—"
            if (snapshot.tombstone) return "待配置"
            if (snapshot.privacy) return "¥ ••••"
            val total = snapshot.total ?: return "待更新"
            return signedMoney(total)
        }

        private fun amountText(value: String?, privacy: Boolean): String {
            if (privacy) return "••••"
            if (value == null) return "—"
            return signedMoney(value, withSymbol = false)
        }

        private fun signedMoney(value: String, withSymbol: Boolean = true): String {
            val negative = value.startsWith("-")
            val digits = if (negative) value.substring(1) else value
            val sign = if (negative) "−" else ""
            val symbol = if (withSymbol) "¥" else ""
            return "$sign$symbol$digits"
        }

        private fun timeText(snapshot: WidgetSnapshot?, stale: Boolean): String {
            if (snapshot == null) return "打开 App 更新"
            val zone = try {
                ZoneId.of(snapshot.timezone)
            } catch (error: Exception) {
                ZoneId.systemDefault()
            }
            val local = Instant.ofEpochMilli(snapshot.computedAt).atZone(zone)
            val prefix = if (stale) "上次更新" else "截至"
            return "$prefix ${TIME_FORMAT.format(local)}"
        }

        private fun openApp(context: Context, link: String, requestCode: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(link), context, MainActivity::class.java)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
