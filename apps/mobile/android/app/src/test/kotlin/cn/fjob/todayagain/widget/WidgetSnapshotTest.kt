package cn.fjob.todayagain.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetSnapshotTest {
    private fun entry(
        revision: Long = 1,
        computedAt: String = "2026-11-04T06:36:00.000Z",
        privacy: Boolean = false,
        tombstone: Boolean = false,
        total: String = "-55.26",
        deepLink: String = "fjob://dashboard",
        extraAmountKey: String? = null,
    ): String {
        val amounts = buildString {
            append("\"total\":").append(if (total == "null") "null" else "\"$total\"")
            append(",\"wage\":\"328.57\",\"stockDaily\":\"-350.00\",\"goldDaily\":\"100.00\"")
            append(",\"housing\":\"97.33\",\"car\":\"36.50\"")
            append(",\"principal\":\"87.19\",\"interest\":\"46.64\",\"rent\":\"0.00\"")
            if (extraAmountKey != null) append(",\"$extraAmountKey\":\"1.00\"")
        }
        return """
            {
              "schemaVersion": 1,
              "ledgerRevision": $revision,
              "createdAt": "2026-11-04T06:36:00.000Z",
              "computedAt": "$computedAt",
              "quotesAsOf": "2026-11-04T06:36:00.000Z",
              "validUntil": "2026-11-04T07:06:00.000Z",
              "timezone": "Asia/Shanghai",
              "privacy": $privacy,
              "tombstone": $tombstone,
              "completeness": "complete",
              "quoteQuality": "fixture",
              "amounts": { $amounts },
              "housingMode": "mortgage",
              "scene": "working",
              "caption": "工资正在努力追赶上午的亏损。",
              "deepLink": "$deepLink"
            }
        """.trimIndent()
    }

    @Test
    fun parsesTheContractFixture() {
        val snapshot = WidgetSnapshot.parse(entry())
        assertNotNull(snapshot)
        assertEquals(1, snapshot!!.schemaVersion)
        assertEquals("-55.26", snapshot.total)
        assertEquals("mortgage", snapshot.housingMode)
        assertTrue(snapshot.isNegative)
        assertEquals(1793774160000L, snapshot.computedAt)
    }

    @Test
    fun rejectsUnsupportedSchemaVersion() {
        val json = entry().replace("\"schemaVersion\": 1", "\"schemaVersion\": 2")
        assertNull(WidgetSnapshot.parse(json))
    }

    @Test
    fun rejectsPrivacyPayloadThatLeaksAmounts() {
        val leaked = entry(privacy = true)
        assertNull(WidgetSnapshot.parse(leaked))
    }

    @Test
    fun rejectsMalformedAmounts() {
        assertNull(WidgetSnapshot.parse(entry(total = "-55.2")))
        assertNull(WidgetSnapshot.parse(entry(total = "55")))
        assertNull(WidgetSnapshot.parse(entry(total = "1,000.00")))
    }

    @Test
    fun rejectsUnknownAmountKeys() {
        assertNull(WidgetSnapshot.parse(entry(extraAmountKey = "bonus")))
    }

    @Test
    fun rejectsTombstonesThatDoNotMaskEverything() {
        assertNull(WidgetSnapshot.parse(entry(tombstone = true)))
    }

    @Test
    fun rejectsUnknownDeepLinks() {
        assertNull(WidgetSnapshot.parse(entry(deepLink = "fjob://admin")))
    }

    @Test
    fun selectsTheLatestEntryThatIsAlreadyDue() {
        val timeline = WidgetTimeline.parse(
            """
            {
              "timelineVersion": 1,
              "ledgerRevision": 3,
              "entries": [
                ${entry(computedAt = "2026-11-04T06:36:00.000Z")},
                ${entry(computedAt = "2026-11-04T06:41:00.000Z")},
                ${entry(computedAt = "2026-11-04T06:46:00.000Z")}
              ]
            }
            """.trimIndent(),
        )
        assertNotNull(timeline)
        val entries = timeline!!.entries
        assertEquals(entries[0].computedAt, timeline.entryFor(entries[0].computedAt)!!.computedAt)
        assertEquals(
            entries[1].computedAt,
            timeline.entryFor(entries[1].computedAt + 1000)!!.computedAt,
        )
        assertEquals(
            entries[2].computedAt,
            timeline.entryFor(entries[2].computedAt + 3600_000)!!.computedAt,
        )
        // Before the first entry the first computed frame is still the closest.
        assertEquals(entries[0].computedAt, timeline.entryFor(0)!!.computedAt)
    }

    @Test
    fun rejectsTimelinesWithTooManyOrNoEntries() {
        val empty = WidgetTimeline.parse(
            """{"timelineVersion":1,"ledgerRevision":1,"entries":[]}""",
        )
        assertNull(empty)
    }

    @Test
    fun rejectsEntriesFromANewerRevision() {
        val json =
            """
            {
              "timelineVersion": 1,
              "ledgerRevision": 1,
              "entries": [ ${entry(revision = 2)} ]
            }
            """.trimIndent()
        assertNull(WidgetTimeline.parse(json))
    }

    @Test
    fun parserHandlesEscapesAndUnicode() {
        val parsed = SnapshotJson.parse("""{"a":"line\nbreak \u4e2d\u6587","b":[1,2.5,true,null]}""")
        val map = parsed as Map<*, *>
        assertEquals("line\nbreak 中文", map["a"])
        assertEquals(listOf(1L, 2.5, true, null), map["b"])
    }
}
