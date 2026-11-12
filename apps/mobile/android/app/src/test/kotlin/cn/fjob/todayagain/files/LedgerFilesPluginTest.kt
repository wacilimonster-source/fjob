package cn.fjob.todayagain.files

import org.junit.Assert.assertEquals
import org.junit.Test

class LedgerFilesPluginTest {
    @Test
    fun keepsANormalExportName() {
        assertEquals(
            "fjob-2026-11-12.fjob",
            LedgerFilesPlugin.sanitizeFileName("fjob-2026-11-12.fjob"),
        )
    }

    @Test
    fun replacesPathSeparatorsAndReservedCharacters() {
        assertEquals(
            "_etc_passwd_.fjob",
            LedgerFilesPlugin.sanitizeFileName("/etc/passwd?.fjob"),
        )
        assertEquals(
            "a_b_c_d_e_f_.fjob",
            LedgerFilesPlugin.sanitizeFileName("a\\b:c*d\"e<f>.fjob"),
        )
    }

    @Test
    fun removesControlCharacters() {
        assertEquals(
            "fjob_.fjob",
            LedgerFilesPlugin.sanitizeFileName("fjob\u0000.fjob"),
        )
    }

    @Test
    fun blankNameFallsBackToASafeDefault() {
        assertEquals("fjob-export.fjob", LedgerFilesPlugin.sanitizeFileName("   "))
    }

    @Test
    fun truncatesVeryLongNames() {
        assertEquals(
            120,
            LedgerFilesPlugin.sanitizeFileName("a".repeat(300)).length,
        )
    }
}
