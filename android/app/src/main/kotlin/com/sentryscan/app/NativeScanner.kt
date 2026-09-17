package com.sentryscan.app

import android.app.AppOpsManager
import android.app.KeyguardManager
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * Zbira SUROVA dejstva o sistemu in nameščenih aplikacijah preko uradnih
 * (dokumentiranih) Android API-jev, dostopnih navadni (ne-sistemski,
 * ne-rootani) aplikaciji. Namenoma NE vsebuje nobene "je to sumljivo?"
 * logike - vsa interpretacija/ocenjevanje tveganja se zgodi v Dart
 * `heuristics_engine.dart`, da je oceno tveganja lažje preverjati in
 * spreminjati brez poseganja v native kodo.
 *
 * Znane omejitve (namenoma brez "trikov" za obhod - so del poštene ocene
 * zmožnosti aplikacije brez root dostopa):
 *  - Ni mogoče prebrati porabe baterije PO APLIKACIJI (BatteryStats/
 *    BatteryUsageStats API zahteva sistemsko/privilegirano dovoljenje
 *    BATTERY_STATS). Namesto tega uporabljamo posredne kazalnike: standby
 *    "bucket" (oceno OS-a, kako aktivna je aplikacija), izjeme od
 *    optimizacije baterije in skupni čas v ospredju (UsageStats).
 *  - `ActivityManager.getRunningServices()` od Androida 5+ za aplikacije
 *    tretjih oseb vrača samo lastne storitve klicatelja, zato ni
 *    uporabljen za druge aplikacije.
 *  - Seznam aktivnih "device admin" aplikacij in enakih virov je
 *    "best effort" - na nekaterih OEM ROM-ih se lahko obnaša druga
 *    (glej komentar pri getActiveDeviceAdmins).
 */
object NativeScanner {

    // ---------------------------------------------------------------
    // Nameščene aplikacije
    // ---------------------------------------------------------------

    @Suppress("DEPRECATION")
    fun getInstalledApps(context: Context): List<Map<String, Any?>> {
        val pm = context.packageManager
        val flags = PackageManager.GET_PERMISSIONS or signingFlag()
        val packages: List<PackageInfo> = try {
            pm.getInstalledPackages(flags)
        } catch (t: Throwable) {
            emptyList()
        }

        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val standbyBuckets = getStandbyBucketsSafe(context)

        return packages.mapNotNull { pi ->
            try {
                packageInfoToMap(context, pm, pi, powerManager, standbyBuckets)
            } catch (t: Throwable) {
                null
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun packageInfoToMap(
        context: Context,
        pm: PackageManager,
        pi: PackageInfo,
        powerManager: PowerManager?,
        standbyBuckets: Map<String, Int>,
    ): Map<String, Any?> {
        val appInfo: ApplicationInfo = pi.applicationInfo ?: return emptyMap()
        val packageName = pi.packageName

        val label = try {
            pm.getApplicationLabel(appInfo).toString()
        } catch (t: Throwable) {
            packageName
        }

        val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
        val isUpdatedSystemApp = (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
        val hasLauncherIcon = pm.getLaunchIntentForPackage(packageName) != null

        val installer: String? = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                pm.getInstallSourceInfo(packageName).installingPackageName
            } else {
                pm.getInstallerPackageName(packageName)
            }
        } catch (t: Throwable) {
            null
        }

        val requestedPermissions: List<String> = pi.requestedPermissions?.toList() ?: emptyList()
        val grantedPermissions: List<String> = buildList {
            val flagsArr = pi.requestedPermissionsFlags
            if (flagsArr != null) {
                for (i in requestedPermissions.indices) {
                    if (i < flagsArr.size &&
                        (flagsArr[i] and PackageInfo.REQUESTED_PERMISSION_GRANTED) != 0
                    ) {
                        add(requestedPermissions[i])
                    }
                }
            }
        }

        val signingCertSha256: String? = try {
            extractSigningCertSha256(pi)
        } catch (t: Throwable) {
            null
        }

        val apkPath = appInfo.sourceDir
        val apkSizeBytes = try {
            apkPath?.let { File(it).length() } ?: 0L
        } catch (t: Throwable) {
            0L
        }

        val isIgnoringBatteryOptimizations = try {
            powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
        } catch (t: Throwable) {
            false
        }

        val versionCode = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) pi.longVersionCode else pi.versionCode.toLong()
        } catch (t: Throwable) {
            0L
        }

        return mapOf(
            "packageName" to packageName,
            "appLabel" to label,
            "versionName" to pi.versionName,
            "versionCode" to versionCode,
            "firstInstallTime" to pi.firstInstallTime,
            "lastUpdateTime" to pi.lastUpdateTime,
            "installerPackageName" to installer,
            "isSystemApp" to isSystemApp,
            "isUpdatedSystemApp" to isUpdatedSystemApp,
            "hasLauncherIcon" to hasLauncherIcon,
            "requestedPermissions" to requestedPermissions,
            "grantedPermissions" to grantedPermissions,
            "signingCertSha256" to signingCertSha256,
            "apkPath" to apkPath,
            "apkSizeBytes" to apkSizeBytes,
            "isIgnoringBatteryOptimizations" to isIgnoringBatteryOptimizations,
            "standbyBucket" to standbyBuckets[packageName],
        )
    }

    private fun signingFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
    }

    @Suppress("DEPRECATION")
    private fun extractSigningCertSha256(pi: PackageInfo): String? {
        val bytes: ByteArray? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = pi.signingInfo ?: return null
            val certs = if (info.hasMultipleSigners()) info.apkContentsSigners else info.signingCertificateHistory
            certs?.firstOrNull()?.toByteArray()
        } else {
            pi.signatures?.firstOrNull()?.toByteArray()
        }
        return bytes?.let { sha256Hex(it) }
    }

    private fun getStandbyBucketsSafe(context: Context): Map<String, Int> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return emptyMap()
        return try {
            val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                ?: return emptyMap()
            usm.appStandbyBuckets
        } catch (t: Throwable) {
            // Zahteva odobren dostop do "Usage access" - brez njega vrne prazno.
            emptyMap()
        }
    }

    // ---------------------------------------------------------------
    // APK SHA-256 (za VirusTotal poizvedbo) - na zahtevo, po paketu
    // ---------------------------------------------------------------

    fun computeApkSha256(context: Context, packageName: String): String? {
        return try {
            val appInfo = context.packageManager.getApplicationInfo(packageName, 0)
            val path = appInfo.sourceDir ?: return null
            sha256OfFile(path)
        } catch (t: Throwable) {
            null
        }
    }

    private fun sha256OfFile(path: String): String? {
        return try {
            val digest = MessageDigest.getInstance("SHA-256")
            FileInputStream(path).use { input ->
                val buffer = ByteArray(1 shl 16)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    digest.update(buffer, 0, read)
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        } catch (t: Throwable) {
            null
        }
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    // ---------------------------------------------------------------
    // Sistemski varnostni posnetek (surova dejstva, brez ocene)
    // ---------------------------------------------------------------

    @Suppress("DEPRECATION")
    fun getSystemSecuritySnapshot(context: Context): Map<String, Any?> {
        val cr = context.contentResolver

        val enabledAccessibilityServices = try {
            Settings.Secure.getString(cr, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                ?.split(":")?.filter { it.isNotBlank() } ?: emptyList()
        } catch (t: Throwable) {
            emptyList()
        }

        val enabledNotificationListeners = try {
            Settings.Secure.getString(cr, "enabled_notification_listeners")
                ?.split(":")?.filter { it.isNotBlank() } ?: emptyList()
        } catch (t: Throwable) {
            emptyList()
        }

        val activeDeviceAdmins = getActiveDeviceAdmins(context)

        val adbEnabled = try {
            Settings.Global.getInt(cr, Settings.Global.ADB_ENABLED, 0) == 1
        } catch (t: Throwable) {
            false
        }

        val developerOptionsEnabled = try {
            Settings.Global.getInt(cr, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1
        } catch (t: Throwable) {
            false
        }

        val isDeviceEncrypted = try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
            val status = dpm?.storageEncryptionStatus
            status == DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE ||
                status == DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_PER_USER
        } catch (t: Throwable) {
            false
        }

        val (hasActiveVpn, proxyDescription) = getNetworkSecurityFacts(context)

        val screenLockEnabled = try {
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            km?.isDeviceSecure ?: false
        } catch (t: Throwable) {
            false
        }

        val usageAccessGranted = isUsageAccessGranted(context)

        val installedPackageNames = try {
            context.packageManager.getInstalledPackages(0).map { it.packageName }.toSet()
        } catch (t: Throwable) {
            emptySet()
        }
        val rootCheck = RootDetector.check(installedPackageNames)

        return mapOf(
            "enabledAccessibilityServices" to enabledAccessibilityServices,
            "enabledNotificationListeners" to enabledNotificationListeners,
            "activeDeviceAdmins" to activeDeviceAdmins,
            "adbEnabled" to adbEnabled,
            "developerOptionsEnabled" to developerOptionsEnabled,
            "isDeviceEncrypted" to isDeviceEncrypted,
            "hasActiveVpn" to hasActiveVpn,
            "httpProxyDescription" to proxyDescription,
            "screenLockEnabled" to screenLockEnabled,
            "usageAccessGranted" to usageAccessGranted,
            "isLikelyRooted" to rootCheck.isLikelyRooted,
            "rootIndicators" to rootCheck.indicators,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "buildFingerprint" to Build.FINGERPRINT,
            "buildTags" to (Build.TAGS ?: ""),
        )
    }

    /**
     * `DevicePolicyManager.getActiveAdmins()` na navadni (ne device-owner)
     * aplikaciji vrne komponente VSEH aktivnih skrbnikov naprave, ne le
     * lastnih - to je uradno dokumentirano vedenje in ga uporabljajo tudi
     * znane anti-stalkerware aplikacije. Nekateri OEM ROM-i (predvsem
     * MIUI/EMUI z agresivnimi App-Ops omejitvami) lahko vrnejo prazen
     * seznam kljub obstoječim skrbnikom - zato je to označeno kot
     * "best effort" v UI in poročilu.
     */
    private fun getActiveDeviceAdmins(context: Context): List<String> {
        return try {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
                ?: return emptyList()
            dpm.activeAdmins?.map { it.flattenToString() } ?: emptyList()
        } catch (t: Throwable) {
            emptyList()
        }
    }

    private fun getNetworkSecurityFacts(context: Context): Pair<Boolean, String?> {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return false to null
            val network = cm.activeNetwork ?: return false to null
            val caps = cm.getNetworkCapabilities(network)
            val hasVpn = caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true

            val proxy = cm.getLinkProperties(network)?.httpProxy
            val proxyDescription = proxy?.let { "${it.host}:${it.port}" }

            hasVpn to proxyDescription
        } catch (t: Throwable) {
            false to null
        }
    }

    private fun isUsageAccessGranted(context: Context): Boolean {
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    context.packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    context.packageName,
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (t: Throwable) {
            false
        }
    }

    // ---------------------------------------------------------------
    // Uporaba aplikacij (zahteva "Usage access")
    // ---------------------------------------------------------------

    fun getUsageStats(context: Context, days: Int): List<Map<String, Any?>> {
        if (!isUsageAccessGranted(context)) return emptyList()
        return try {
            val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val end = System.currentTimeMillis()
            val start = end - days.toLong() * 24L * 60L * 60L * 1000L
            val stats = usm.queryAndAggregateUsageStats(start, end)
            stats.values
                .filter { it.totalTimeInForeground > 0 }
                .map {
                    mapOf(
                        "packageName" to it.packageName,
                        "totalForegroundTimeMs" to it.totalTimeInForeground,
                        "lastTimeUsed" to it.lastTimeUsed,
                    )
                }
        } catch (t: Throwable) {
            emptyList()
        }
    }

    // ---------------------------------------------------------------
    // Trenutni posnetek baterije
    // ---------------------------------------------------------------

    fun getBatterySnapshot(context: Context): Map<String, Any?> {
        val intent = context.registerReceiver(
            null,
            android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )

        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val pct = if (level >= 0 && scale > 0) (level * 100) / scale else -1

        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL

        val pluggedRaw = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
        val pluggedType = when (pluggedRaw) {
            BatteryManager.BATTERY_PLUGGED_AC -> "AC"
            BatteryManager.BATTERY_PLUGGED_USB -> "USB"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "WIRELESS"
            else -> "NONE"
        }

        val healthRaw = intent?.getIntExtra(BatteryManager.EXTRA_HEALTH, -1) ?: -1
        val health = when (healthRaw) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "GOOD"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "OVERHEAT"
            BatteryManager.BATTERY_HEALTH_DEAD -> "DEAD"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "OVER_VOLTAGE"
            BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "UNSPECIFIED_FAILURE"
            BatteryManager.BATTERY_HEALTH_COLD -> "COLD"
            else -> "UNKNOWN"
        }

        val temperatureTenths = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        val temperatureC = if (temperatureTenths >= 0) temperatureTenths / 10.0 else null

        val voltageMv = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)?.takeIf { it > 0 }
        val technology = intent?.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY)

        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val currentNowMicroAmps = try {
            bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
                ?.takeIf { it != Int.MIN_VALUE }
        } catch (t: Throwable) {
            null
        }
        val chargeCounterMicroAh = try {
            bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
                ?.takeIf { it != Int.MIN_VALUE }
        } catch (t: Throwable) {
            null
        }

        return mapOf(
            "timestampMs" to System.currentTimeMillis(),
            "levelPercent" to pct,
            "isCharging" to isCharging,
            "pluggedType" to pluggedType,
            "health" to health,
            "temperatureC" to temperatureC,
            "voltageMv" to voltageMv,
            "technology" to technology,
            "currentNowMicroAmps" to currentNowMicroAmps,
            "chargeCounterMicroAh" to chargeCounterMicroAh,
        )
    }

    // ---------------------------------------------------------------
    // Zgodovina baterije (datoteka, ki jo polni BatterySamplerWorker)
    // ---------------------------------------------------------------

    fun historyFile(context: Context): File = File(context.filesDir, "battery_history.jsonl")

    fun appendBatterySample(context: Context, sample: Map<String, Any?>) {
        try {
            val file = historyFile(context)
            val json = org.json.JSONObject(sample as Map<*, *>)
            file.appendText(json.toString() + "\n")
            trimHistoryFileIfNeeded(file)
        } catch (t: Throwable) {
            // Napaka pri beleženju enega vzorca ne sme sesuti worker/klicatelja.
        }
    }

    private fun trimHistoryFileIfNeeded(file: File, maxLines: Int = 6000, keepLines: Int = 4000) {
        try {
            if (!file.exists()) return
            val lines = file.readLines()
            if (lines.size > maxLines) {
                file.writeText(lines.takeLast(keepLines).joinToString("\n") + "\n")
            }
        } catch (t: Throwable) {
            // ignoriraj - obrezovanje ni kritično
        }
    }

    fun readBatteryHistory(context: Context, sinceEpochMs: Long): List<Map<String, Any?>> {
        val file = historyFile(context)
        if (!file.exists()) return emptyList()
        return try {
            file.readLines()
                .mapNotNull { line ->
                    try {
                        val obj = org.json.JSONObject(line)
                        val ts = obj.optLong("timestampMs", 0L)
                        if (ts < sinceEpochMs) return@mapNotNull null
                        jsonObjectToMap(obj)
                    } catch (t: Throwable) {
                        null
                    }
                }
        } catch (t: Throwable) {
            emptyList()
        }
    }

    private fun jsonObjectToMap(obj: org.json.JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = if (obj.isNull(key)) null else obj.get(key)
        }
        return map
    }

    // ---------------------------------------------------------------
    // Odpiranje sistemskih nastavitev, ki jih ni mogoče zahtevati z
    // navadnim runtime dialogom
    // ---------------------------------------------------------------

    fun openSpecialSetting(context: Context, target: String) {
        val intent = when (target) {
            "usage_access" -> Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                putExtra("android.provider.extra.APP_PACKAGE", context.packageName)
            }
            "accessibility_settings" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "notification_listener_settings" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            "security_settings" -> Intent(Settings.ACTION_SECURITY_SETTINGS)
            "battery_optimization_all" -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            "request_ignore_battery_optimizations_self" ->
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:${context.packageName}")
                }
            else -> Intent(Settings.ACTION_SETTINGS)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(intent)
        } catch (t: Throwable) {
            // nekateri OEM ROM-i nimajo vseh teh zaslonov - tiho prezri
        }
    }

    fun openAppDetailsSettings(context: Context, packageName: String) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
        } catch (t: Throwable) {
            // ignoriraj
        }
    }
}
