package com.sentryscan.app

import android.os.Build
import java.io.File

/**
 * Heuristična (ne 100% zanesljiva) zaznava rootanja naprave. Enak pristop kot
 * ga uporabljajo znane knjižnice (npr. RootBeer): kombinacija več šibkih
 * signalov je precej zanesljivejša kot kateri koli posamezen test, zato vsak
 * pozitiven test le doda razlog v seznam, končno odločitev pa naredi klicatelj
 * (2+ neodvisna zadetka = visoka verjetnost).
 */
object RootDetector {

    private val SU_PATHS = listOf(
        "/system/bin/su",
        "/system/xbin/su",
        "/sbin/su",
        "/system/su",
        "/system/bin/.ext/su",
        "/system/usr/we-need-root/su",
        "/cache/su",
        "/data/su",
        "/system/xbin/busybox",
    )

    private val ROOT_MANAGEMENT_PACKAGES = listOf(
        "com.topjohnwu.magisk",
        "eu.chainfire.supersu",
        "com.noshufou.android.su",
        "com.noshufou.android.su.elite",
        "com.koushikdutta.superuser",
        "com.thirdparty.superuser",
        "com.yellowes.su",
        "com.kingroot.kinguser",
        "com.kingo.root",
        "com.smedialink.oneclickroot",
        "com.zhiqupk.root.global",
        "com.alephzain.framaroot",
    )

    data class RootCheckResult(val isLikelyRooted: Boolean, val indicators: List<String>)

    fun check(installedPackageNames: Set<String>): RootCheckResult {
        val indicators = mutableListOf<String>()

        for (path in SU_PATHS) {
            if (File(path).exists()) {
                indicators.add("Najdena datoteka: $path")
            }
        }

        for (pkg in ROOT_MANAGEMENT_PACKAGES) {
            if (installedPackageNames.contains(pkg)) {
                indicators.add("Nameščena aplikacija za upravljanje root dostopa: $pkg")
            }
        }

        if (Build.TAGS != null && Build.TAGS.contains("test-keys")) {
            indicators.add("Sistemska slika je podpisana s 'test-keys' (ni uradna proizvajalčeva slika)")
        }

        if (canExecuteSu()) {
            indicators.add("Ukaz 'su' se je uspešno izvedel")
        }

        // Dva ali več neodvisnih znakov = precej zanesljiva ocena.
        val likelyRooted = indicators.size >= 2
        return RootCheckResult(likelyRooted, indicators)
    }

    private fun canExecuteSu(): Boolean {
        var process: Process? = null
        return try {
            process = ProcessBuilder("su", "-c", "id").redirectErrorStream(true).start()
            val finished = process.waitFor(300, java.util.concurrent.TimeUnit.MILLISECONDS)
            finished && process.exitValue() == 0
        } catch (t: Throwable) {
            false
        } finally {
            process?.destroy()
        }
    }
}
