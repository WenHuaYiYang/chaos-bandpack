package com.chaos.bandpack.data.icon

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

class CalendarPreviewTest {
    @Test fun `星期和日期取实际日期且不补零`() {
        val monday = LocalDate.of(2026, 9, 28)
        val expected = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
        expected.forEachIndexed { offset, week ->
            assertEquals(week, CalendarPreview.week(monday.plusDays(offset.toLong())))
        }
        assertEquals("1", CalendarPreview.day(LocalDate.of(2026, 10, 1)))
        assertEquals("29", CalendarPreview.day(LocalDate.of(2028, 2, 29)))
        assertEquals("31", CalendarPreview.day(LocalDate.of(2026, 12, 31)))
    }
}
