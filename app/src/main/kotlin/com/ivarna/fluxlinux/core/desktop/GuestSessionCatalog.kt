package com.ivarna.fluxlinux.core.desktop

/**
 * Which desktop session a guest boots into.
 *
 * Every guest before Omarchy ran XFCE4, so the session was implicit: start
 * scripts hardcoded `startxfce4` and install verification looked for that one
 * binary. Omarchy is an i3 guest, so the session became a real axis.
 *
 * The catalog is the Kotlin half of the SSOT. The guest half is
 * `/etc/fluxlinux/session`, written by the family setup script and read back by
 * `start_gui.sh` / `start_guest_gui.sh` — the same file-in-the-rootfs pattern
 * `/etc/fluxlinux/gpu_mode` already uses. Kotlin decides what to install and
 * what proves it installed; the guest file decides what actually execs, so a
 * guest stays launchable even when the app has forgotten what it installed.
 */
object GuestSessionCatalog {

    /** XFCE4 — the default for every guest that does not opt out. */
    const val XFCE = "xfce"

    /** i3 tiling WM + polybar/rofi/dunst/picom (Omarchy-style guests). */
    const val I3 = "i3"

    /** Session id for [distroId]. Unknown ids fall back to [XFCE]. */
    fun sessionFor(distroId: String): String = when (distroId) {
        "omarchy", "omarchy_chroot" -> I3
        else -> XFCE
    }

    /**
     * Rootfs-relative paths that prove [session] is installed — any one hit is
     * enough. `startxfce4` lives in sbin on some guests; i3 in /usr/local/bin
     * when it was built rather than packaged.
     */
    fun sessionBinaries(session: String): List<String> = when (session) {
        I3 -> listOf("usr/bin/i3", "usr/local/bin/i3")
        else -> listOf("usr/bin/startxfce4", "usr/sbin/startxfce4")
    }

    /** Same as [sessionBinaries], resolved against a chroot rootfs path. */
    fun sessionBinariesIn(chrootPath: String, session: String): List<String> =
        sessionBinaries(session).map { "$chrootPath/$it" }

    /** Human-readable session name for install logs and failure messages. */
    fun displayName(session: String): String = when (session) {
        I3 -> "i3"
        else -> "XFCE"
    }

    /** The binary a start script execs under dbus for [session]. */
    fun launchCommand(session: String): String = when (session) {
        I3 -> "flux-i3-session"
        else -> "startxfce4"
    }
}
