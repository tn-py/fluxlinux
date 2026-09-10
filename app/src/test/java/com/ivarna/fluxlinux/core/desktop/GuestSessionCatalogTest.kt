package com.ivarna.fluxlinux.core.desktop

import com.ivarna.fluxlinux.core.data.DistroRepository
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The session axis added for Omarchy. Every guest that existed before it must
 * still resolve to XFCE, or an app update would break their launch path.
 */
class GuestSessionCatalogTest {

    @Test
    fun omarchyCards_areI3() {
        assertEquals(GuestSessionCatalog.I3, GuestSessionCatalog.sessionFor("omarchy"))
        assertEquals(GuestSessionCatalog.I3, GuestSessionCatalog.sessionFor("omarchy_chroot"))
    }

    @Test
    fun everyOtherCard_staysXfce() {
        DistroRepository.supportedDistros
            .filterNot { it.id.startsWith("omarchy") }
            .forEach { distro ->
                assertEquals(
                    "${distro.id} must keep the XFCE session",
                    GuestSessionCatalog.XFCE,
                    GuestSessionCatalog.sessionFor(distro.id)
                )
            }
    }

    @Test
    fun unknownDistro_fallsBackToXfce() {
        assertEquals(GuestSessionCatalog.XFCE, GuestSessionCatalog.sessionFor(""))
        assertEquals(GuestSessionCatalog.XFCE, GuestSessionCatalog.sessionFor("not-a-distro"))
    }

    @Test
    fun launchCommands_matchWhatTheStartScriptsExec() {
        // start_gui.sh and start_guest_gui.sh hardcode these two names.
        assertEquals("startxfce4", GuestSessionCatalog.launchCommand(GuestSessionCatalog.XFCE))
        assertEquals("flux-i3-session", GuestSessionCatalog.launchCommand(GuestSessionCatalog.I3))
        assertEquals("startxfce4", GuestSessionCatalog.launchCommand("nonsense"))
    }

    @Test
    fun sessionBinaries_areRootfsRelative_andNonEmpty() {
        listOf(GuestSessionCatalog.XFCE, GuestSessionCatalog.I3).forEach { session ->
            val bins = GuestSessionCatalog.sessionBinaries(session)
            assertTrue("$session has no probe binaries", bins.isNotEmpty())
            bins.forEach { assertFalse("$it must be rootfs-relative", it.startsWith("/")) }
        }
    }

    @Test
    fun sessionBinariesIn_joinsUnderTheChrootRoot() {
        val paths = GuestSessionCatalog.sessionBinariesIn("/data/local/tmp/chrootOmarchy", GuestSessionCatalog.I3)
        assertTrue(paths.contains("/data/local/tmp/chrootOmarchy/usr/bin/i3"))
        assertTrue(paths.all { it.startsWith("/data/local/tmp/chrootOmarchy/") })
    }

    @Test
    fun xfceProbe_stillCoversSbin() {
        val bins = GuestSessionCatalog.sessionBinaries(GuestSessionCatalog.XFCE)
        assertTrue(bins.contains("usr/bin/startxfce4"))
        assertTrue(bins.contains("usr/sbin/startxfce4"))
    }

    @Test
    fun displayNames_areHumanReadable() {
        assertEquals("XFCE", GuestSessionCatalog.displayName(GuestSessionCatalog.XFCE))
        assertEquals("i3", GuestSessionCatalog.displayName(GuestSessionCatalog.I3))
    }
}
