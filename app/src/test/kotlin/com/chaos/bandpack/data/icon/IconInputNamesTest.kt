package com.chaos.bandpack.data.icon

import com.chaos.bandpack.data.DeviceTarget
import org.junit.Assert.*
import org.junit.Test

class IconInputNamesTest {
    @Test fun gifAndCustomCoverArePairedRegardlessOfSelectionOrder() {
        for (names in listOf(listOf("activities.gif", "activities.png"), listOf("activities.png", "activities.gif"), listOf("activities_anim.bin", "activities.bin"))) {
            val plan = IconInputNames.plan(names, DeviceTarget.TEN_PRO)
            assertEquals(0, plan.unmatched); assertEquals(1, plan.groups.size)
            assertNull(plan.groups.single().error)
        }
        assertEquals("weather", IconInputNames.match("天气_anim.bin", DeviceTarget.TEN_PRO)!!.first)
        assertEquals("weather", IconInputNames.match("WEATHER.GIF", DeviceTarget.TEN_PRO)!!.first)
    }

    @Test fun ambiguousCoverAndAnimationSourcesAreRejectedAsOneGroup() {
        for (names in listOf(listOf("weather.png", "weather.bin"), listOf("weather.gif", "weather_anim.bin"), listOf("weather.png", "天气.jpg"))) {
            val plan = IconInputNames.plan(names, DeviceTarget.TEN_PRO)
            assertNotNull(plan.groups.single().error)
        }
        val partial = IconInputNames.plan(listOf("weather.png", "weather.bin", "alarm.png", "unknown.gif"), DeviceTarget.TEN_PRO)
        assertEquals(1, partial.unmatched)
        assertEquals(1, partial.groups.count { it.error == null })
        assertEquals("alarm", partial.groups.single { it.error == null }.stem)
        assertNull(IconInputNames.match("../weather.png", DeviceTarget.TEN_PRO))
        assertNull(IconInputNames.match("weather.txt", DeviceTarget.TEN_PRO))
    }
}
