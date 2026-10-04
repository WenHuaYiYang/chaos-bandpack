package com.chaos.bandpack.ui.screen

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * 批量导入时"文件名怎么对到槽位"的单测。
 *
 * 这条规则是**用户唯一能预判的约定**（他得按这个去命名文件），所以边界必须钉死：
 * 只认精确的英文槽位名或中文显示名，**不做模糊匹配** —— 猜错会把图塞进用户没想改的槽位，
 * 而他未必立刻发现。
 */
class IconNameMatchTest {

    @Test
    fun `英文槽位名可以带任意扩展名`() {
        assertEquals("weather", stemForFileName("weather.png"))
        assertEquals("weather", stemForFileName("weather.jpg"))
        assertEquals("weather", stemForFileName("weather"))
        assertEquals("activities", stemForFileName("activities.webp"))
    }

    @Test
    fun `英文名不分大小写`() {
        assertEquals("weather", stemForFileName("WEATHER.PNG"))
        assertEquals("weather", stemForFileName("Weather.png"))
    }

    @Test
    fun `中文显示名也认`() {
        assertEquals("weather", stemForFileName("天气.png"))
        assertEquals("activities", stemForFileName("活力指标.png"))
        assertEquals("share", stemForFileName("融合设备中心.png"))
        assertEquals("sports_course", stemForFileName("跑步课程.png"))
    }

    @Test
    fun `名字两侧的空格会被去掉`() {
        assertEquals("weather", stemForFileName("  天气  .png"))
        assertEquals("weather", stemForFileName(" weather .png"))
    }

    @Test
    fun `不做模糊匹配`() {
        // 这几条都是"看起来像但不确定"的名字, 宁可报"对不上"让用户改文件名,
        // 也不要猜。尤其 weather_line 这种, 猜成 weather 会把用户另一套图覆盖掉。
        assertNull(stemForFileName("weather_line.png"))
        assertNull(stemForFileName("weather_2.png"))
        assertNull(stemForFileName("天气 拷贝.png"))
        assertNull(stemForFileName("my_weather.png"))
    }

    @Test
    fun `认不出来的一律返回 null`() {
        assertNull(stemForFileName("IMG_0234.png"))
        assertNull(stemForFileName(""))
        assertNull(stemForFileName("   "))
        assertNull(stemForFileName(".png"))
        assertNull(stemForFileName("随便什么名字.png"))
    }

    @Test
    fun `只切最后一个扩展名, 名字里多余的点会保留`() {
        // 规则是"去掉最后一个点之后的部分", 不是"取第一个点之前的部分"。
        // 所以 `天气.v2.png` 得到的是 `天气.v2`, 对不上任何槽位 —— 这是**刻意**的:
        // 换成"取第一个点之前"会让 `my.icon.weather.png` 这类名字被切坏,
        // 而两种切法都只是猜用户怎么命名。猜错不如报"对不上"让他改名。
        assertNull(stemForFileName("天气.v2.png"))
        assertNull(stemForFileName("icon.weather.png"))
    }
    @Test fun `日历日程与分类中文名分别精准匹配`() {
        assertEquals("calendar", stemForFileName("calendar.png"))
        assertEquals("calendar", stemForFileName("日程.png"))
        assertEquals("calendar", stemForFileName("桌面_日程.png"))
        assertEquals("perpetual_calendar", stemForFileName("perpetual_calendar.png"))
        assertEquals("perpetual_calendar", stemForFileName("日历.png"))
        assertEquals("perpetual_calendar", stemForFileName("桌面_日历.png"))
        assertNull(stemForFileName("calendar_background.png"))
        assertEquals("ctrl_disturb", stemForFileName("控制中心_勿扰.png"))
        assertEquals("set_disturb", stemForFileName("设置_勿扰.png"))
        assertEquals("ctrl_flashlight", stemForFileName("CTRL_FLASHLIGHT.png"))
        assertNull(stemForFileName("勿扰.png"))
        assertNull(stemForFileName("运动.png"))
        assertNull(stemForFileName("ctrl_phone_conn.png"))
        assertNull(stemForFileName("蓝牙.png"))
    }

}
