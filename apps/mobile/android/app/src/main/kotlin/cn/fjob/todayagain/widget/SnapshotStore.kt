package cn.fjob.todayagain.widget

import android.content.Context

/**
 * SharedPreferences store for the newest accepted timeline.
 *
 * The payload is written only after it parses and its ledger revision is at
 * least the stored one, so a slow publish can never roll back privacy or
 * resurrect a cleared ledger.
 */
class SnapshotStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun storedRevision(): Long = prefs.getLong(KEY_REVISION, -1L)

    fun storedKind(): String = prefs.getString(KEY_KIND, KIND_NONE) ?: KIND_NONE

    /** Returns false when the payload was rejected or malformed. */
    fun storeTimeline(payload: String): Boolean {
        val timeline = WidgetTimeline.parse(payload) ?: return false
        return store(payload, timeline.ledgerRevision, KIND_TIMELINE)
    }

    /** Accepts only a tombstone that is not older than the stored revision. */
    fun storeTombstone(payload: String): Boolean {
        val timeline = WidgetTimeline.parse(payload) ?: return false
        val entry = timeline.entries.firstOrNull() ?: return false
        if (!entry.tombstone) return false
        return store(payload, timeline.ledgerRevision, KIND_TOMBSTONE)
    }

    private fun store(payload: String, revision: Long, kind: String): Boolean {
        if (revision < storedRevision()) return false
        prefs.edit()
            .putLong(KEY_REVISION, revision)
            .putString(KEY_KIND, kind)
            .putString(KEY_PAYLOAD, payload)
            .apply()
        return true
    }

    fun loadTimeline(): WidgetTimeline? {
        if (storedKind() != KIND_TIMELINE) return null
        val payload = prefs.getString(KEY_PAYLOAD, null) ?: return null
        return WidgetTimeline.parse(payload)
    }

    fun loadTombstone(): WidgetSnapshot? {
        if (storedKind() != KIND_TOMBSTONE) return null
        val payload = prefs.getString(KEY_PAYLOAD, null) ?: return null
        return WidgetTimeline.parse(payload)?.entries?.firstOrNull()
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val PREFS_NAME = "fjob_widget_snapshot"
        private const val KEY_REVISION = "ledger_revision"
        private const val KEY_KIND = "payload_kind"
        private const val KEY_PAYLOAD = "payload"
        const val KIND_TIMELINE = "timeline"
        const val KIND_TOMBSTONE = "tombstone"
        const val KIND_NONE = "none"
    }
}
