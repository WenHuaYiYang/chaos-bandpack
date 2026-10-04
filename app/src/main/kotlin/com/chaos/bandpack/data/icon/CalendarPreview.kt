package com.chaos.bandpack.data.icon

import java.time.LocalDate

/** 日历的背景、星期与日期布局。 */
object CalendarPreview {
    const val WEEK_TOP = 15f
    const val WEEK_SIZE = 24f
    const val WEEK_COLOR = 0xff3482ff.toInt()
    const val DAY_TOP = 38f
    const val DAY_SIZE = 48f
    const val DAY_COLOR = 0xff1a1a1a.toInt()

    fun week(date: LocalDate): String = "周" + "一二三四五六日"[date.dayOfWeek.value - 1]
    fun day(date: LocalDate): String = date.dayOfMonth.toString()
}
