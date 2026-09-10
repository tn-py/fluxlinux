package com.ivarna.fluxlinux.core.install

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Contracts the Omarchy-style guest scripts must hold. These are the failure
 * modes that only show up on a phone, minutes into an install, so they are
 * pinned here instead.
 */
class OmarchyScriptContractTest {

    private fun repoFile(rel: String): File {
        val cwd = File("").absoluteFile
        val candidates = listOf(
            File(cwd, rel),
            File(cwd, "app/$rel"),
            File(cwd.parentFile, rel),
            File(cwd.parentFile, "app/$rel")
        )
        return candidates.firstOrNull { it.isFile }
            ?: error("missing $rel (cwd=$cwd)")
    }

    /** Script body with comment lines dropped — these files name what they
     *  deliberately exclude, and that prose must not read as usage. */
    private fun code(text: String): String = text.lineSequence()
        .map { it.trim() }
        .filterNot { it.startsWith("#") || it.isEmpty() }
        .joinToString("\n")

    private val family by lazy {
        repoFile("src/main/assets/scripts/omarchy/common/setup/setup_omarchy_family.sh").readText()
    }
    private val custom by lazy {
        repoFile("src/main/assets/scripts/omarchy/common/setup/setup_customization_omarchy.sh").readText()
    }

    @Test
    fun family_keepsAlarmMirrors_neverOmarchyOrManjaro() {
        assertTrue(family.contains("archlinuxarm"))
        assertFalse(
            "stable-mirror.omarchy.org is x86_64-only — writing it breaks every later pacman call",
            code(family).contains("mirror.omarchy.org")
        )
        assertFalse(
            "must not write Manjaro arm-stable mirrors",
            Regex("""Server\s*=\s*\S*arm-stable""").containsMatchIn(code(family))
        )
    }

    @Test
    fun family_disablesSandboxAndCheckSpace() {
        // Android has no Landlock, and bind mounts lie about free space.
        assertTrue(family.contains("DisableSandbox"))
        assertTrue(family.contains("CheckSpace"))
    }

    @Test
    fun family_neverInstallsWaylandOnlyPackages() {
        // Hyprland's backend (aquamarine) has no X11 path, and the rest have no
        // ALARM aarch64 build — any one of them would fail the whole pacman
        // call and take the guest down with it. The names may appear in
        // comments explaining why, so only non-comment lines are checked.
        // Tokenise rather than substring-match: "hyprland" must not appear as a
        // package name, but "hyprland-guiutils" in prose is not a package here.
        val tokens = code(family)
            .split(' ', '\t', '\\', '\n')
            .map { it.trim() }
            .toSet()
        listOf("hyprland", "waybar", "hyprlock", "hypridle", "uwsm", "sddm", "plymouth", "walker")
            .forEach { pkg ->
                assertFalse(
                    "$pkg cannot run on the Lorie X server / ALARM aarch64",
                    tokens.contains(pkg)
                )
            }
    }

    @Test
    fun family_writesSessionMarkerAndGpuMode() {
        // start_gui.sh reads /etc/fluxlinux/session; without it the guest would
        // launch startxfce4, which this guest does not have.
        assertTrue(family.contains("_flux_write_session i3"))
        assertTrue(family.contains("_flux_write_gpu_mode"))
    }

    @Test
    fun family_installsTheSessionLauncherTheStartScriptsExec() {
        assertTrue(family.contains("/usr/local/bin/flux-i3-session"))
        assertTrue(family.contains("exec i3"))
    }

    @Test
    fun family_shipsAnI3ConfigSoTheWizardNeverRuns() {
        // Bare i3 with no config launches i3-config-wizard, which blocks on a
        // keypress and reads as a hang on a phone.
        assertTrue(family.contains(".config/i3/config"))
        assertTrue(family.contains("bindsym \$mod+Return"))
    }

    @Test
    fun family_failsClosedOnLocaleAndSession() {
        assertTrue(family.contains("_flux_ensure_en_us_locale || exit 1"))
        assertTrue(family.contains("_flux_require_i3"))
        assertTrue("gzip is required to unpack UTF-8.gz for localedef", family.contains("python sed gzip"))
    }

    @Test
    fun family_optionalPackagesNeverAbortTheInstall() {
        // One missing aarch64 build must not cost the user the whole guest.
        assertTrue(family.contains("_flux_omarchy_optional"))
        assertTrue(family.contains("unavailable on aarch64 — skipped"))
    }

    @Test
    fun family_runsAsRootInsideGuest() {
        assertTrue(family.contains("must run as root inside the guest"))
    }

    @Test
    fun customization_themesTheX11StackNotWayland() {
        listOf("alacritty", "polybar", "rofi", "dunst").forEach {
            assertTrue("customization must theme $it", custom.contains(it))
        }
        // Named in the header comment as the Wayland components being replaced.
        assertFalse(code(custom).contains("waybar"))
        assertFalse(code(custom).contains("mako"))
    }

    @Test
    fun customization_polybarBarNameMatchesTheLauncher() {
        // flux-i3-session runs `polybar --reload flux`; a renamed bar silently
        // shows nothing.
        assertTrue(custom.contains("[bar/flux]"))
        assertTrue(family.contains("polybar --reload flux"))
    }

    @Test
    fun customization_honoursTheSharedThemeAndSkipFlags() {
        assertTrue(custom.contains("FLUX_THEME"))
        assertTrue(custom.contains("FLUX_SKIP_OMZ"))
        assertTrue(custom.contains("FLUX_SKIP_POKEMON"))
    }

    @Test
    fun customization_preservesKeybindingsOnRerun() {
        // Customization rewrites only the palette lines in place, so re-running
        // it can never cost the user the bindings the family script wrote.
        val dollar = '$'
        assertTrue(custom.contains("set \\${dollar}accent "))
        assertTrue(custom.contains("config.fluxnew."))
        assertFalse(
            "customization must not truncate the i3 config the family script wrote",
            custom.contains("cat > \"${dollar}USER_HOME/.config/i3/config\"")
        )
    }

    @Test
    fun startScripts_dispatchOnTheSessionMarker() {
        val proot = repoFile("src/main/assets/scripts/debian/proot/start/start_gui.sh").readText()
        val chroot = repoFile("src/main/assets/scripts/chroot/start_guest_gui.sh").readText()
        listOf(proot to "proot", chroot to "chroot").forEach { (text, which) ->
            assertTrue("$which must read the session marker", text.contains("/etc/fluxlinux/session"))
            assertTrue("$which must know flux-i3-session", text.contains("flux-i3-session"))
            assertTrue(
                "$which must default to xfce when the marker is absent",
                text.contains("FLUX_SESSION=xfce")
            )
        }
    }
}
