package cn.fjob.todayagain.widget

import java.time.Instant

/**
 * Native view of `contracts/widget-snapshot.schema.json`.
 *
 * All amounts arrive pre-computed and pre-rounded by the Dart engine; this
 * class never recalculates wages, allocations or profit and loss.
 */
data class WidgetSnapshot(
    val schemaVersion: Int,
    val ledgerRevision: Long,
    val computedAt: Long,
    val validUntil: Long,
    val timezone: String,
    val privacy: Boolean,
    val tombstone: Boolean,
    val completeness: String,
    val quoteQuality: String,
    val amounts: Map<String, String?>,
    val housingMode: String,
    val scene: String,
    val caption: String,
    val deepLink: String,
) {
    val total: String? get() = amounts["total"]
    val wage: String? get() = amounts["wage"]
    val stockDaily: String? get() = amounts["stockDaily"]
    val goldDaily: String? get() = amounts["goldDaily"]
    val housing: String? get() = amounts["housing"]
    val car: String? get() = amounts["car"]

    val isNegative: Boolean = total?.startsWith("-") == true

    companion object {
        const val SCHEMA_VERSION = 1
        val AMOUNT_KEYS = listOf(
            "total", "wage", "stockDaily", "goldDaily",
            "housing", "car", "principal", "interest", "rent",
        )
        private val AMOUNT_PATTERN = Regex("""^-?(0|[1-9][0-9]*)\.[0-9]{2}$""")
        private val COMPLETENESS = setOf("complete", "partial", "unavailable")
        private val QUALITY = setOf("live", "delayed", "eod", "stale", "unavailable", "fixture")
        private val HOUSING = setOf("mortgage", "rent", "none")
        private val SCENES = setOf("working", "break", "offDuty", "restDay", "unknown")
        private val DEEP_LINKS = setOf(
            "fjob://dashboard", "fjob://expenses/housing",
            "fjob://expenses/car", "fjob://widgets",
        )

        fun parse(json: String): WidgetSnapshot? = try {
            parseValue(SnapshotJson.parse(json))
        } catch (error: IllegalArgumentException) {
            null
        } catch (error: IllegalStateException) {
            null
        }

        fun parseValue(value: Any?): WidgetSnapshot? {
            val map = value as? Map<*, *> ?: return null
            if (map.int("schemaVersion") != SCHEMA_VERSION) return null
            val revision = map.long("ledgerRevision") ?: return null
            val computedAt = map.instant("computedAt") ?: return null
            val validUntil = map.instant("validUntil") ?: return null
            val timezone = map["timezone"] as? String ?: return null
            if (timezone.isBlank()) return null
            val privacy = map["privacy"] as? Boolean ?: return null
            val tombstone = map["tombstone"] as? Boolean ?: return null
            val completeness = map["completeness"] as? String ?: return null
            if (completeness !in COMPLETENESS) return null
            val quality = map["quoteQuality"] as? String ?: return null
            if (quality !in QUALITY) return null
            val housingMode = map["housingMode"] as? String ?: return null
            if (housingMode !in HOUSING) return null
            val scene = map["scene"] as? String ?: return null
            if (scene !in SCENES) return null
            val caption = map["caption"] as? String ?: return null
            if (caption.length > 100) return null
            val deepLink = map["deepLink"] as? String ?: return null
            if (deepLink !in DEEP_LINKS) return null

            val rawAmounts = map["amounts"] as? Map<*, *> ?: return null
            if (rawAmounts.keys.map { it.toString() }.toSet() != AMOUNT_KEYS.toSet()) {
                return null
            }
            val amounts = LinkedHashMap<String, String?>()
            for (key in AMOUNT_KEYS) {
                val amount = rawAmounts[key]
                if (amount == null) {
                    amounts[key] = null
                } else {
                    val text = amount as? String ?: return null
                    if (!AMOUNT_PATTERN.matches(text)) return null
                    amounts[key] = text
                }
            }
            if (privacy && amounts.values.any { it != null }) return null
            if (tombstone) {
                if (completeness != "unavailable" || !privacy) return null
            }

            return WidgetSnapshot(
                schemaVersion = SCHEMA_VERSION,
                ledgerRevision = revision,
                computedAt = computedAt,
                validUntil = validUntil,
                timezone = timezone,
                privacy = privacy,
                tombstone = tombstone,
                completeness = completeness,
                quoteQuality = quality,
                amounts = amounts,
                housingMode = housingMode,
                scene = scene,
                caption = caption,
                deepLink = deepLink,
            )
        }
    }
}

/** A 24-hour pre-computed timeline, published as one atomic payload. */
data class WidgetTimeline(
    val ledgerRevision: Long,
    val entries: List<WidgetSnapshot>,
) {
    /** The latest entry at or before [nowMillis], else the first entry. */
    fun entryFor(nowMillis: Long): WidgetSnapshot? {
        var chosen: WidgetSnapshot? = null
        for (entry in entries) {
            if (entry.computedAt <= nowMillis) chosen = entry else break
        }
        return chosen ?: entries.firstOrNull()
    }

    companion object {
        const val MAX_ENTRIES = 289

        fun parse(json: String): WidgetTimeline? = try {
            val map = SnapshotJson.parse(json) as? Map<*, *> ?: return null
            if (map.int("timelineVersion") != 1) return null
            val revision = map.long("ledgerRevision") ?: return null
            val rawEntries = map["entries"] as? List<*> ?: return null
            if (rawEntries.isEmpty() || rawEntries.size > MAX_ENTRIES) return null
            val typed = ArrayList<WidgetSnapshot>(rawEntries.size)
            for (item in rawEntries) {
                val parsed = WidgetSnapshot.parseValue(item) ?: return null
                typed.add(parsed)
            }
            if (typed.any { it.ledgerRevision > revision }) return null
            WidgetTimeline(revision, typed)
        } catch (error: IllegalArgumentException) {
            null
        }
    }
}

private fun Map<*, *>.int(key: String): Int? = (this[key] as? Number)?.toInt()

private fun Map<*, *>.long(key: String): Long? = (this[key] as? Number)?.toLong()

private fun Map<*, *>.instant(key: String): Long? {
    val text = this[key] as? String ?: return null
    return try {
        Instant.parse(text).toEpochMilli()
    } catch (error: Exception) {
        null
    }
}
