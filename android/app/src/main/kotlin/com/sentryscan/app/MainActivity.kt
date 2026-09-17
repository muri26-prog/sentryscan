package com.sentryscan.app

import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

private const val CHANNEL = "com.sentryscan.app/native"
private const val BATTERY_WORK_NAME = "sentryscan_battery_sampler"

class MainActivity : FlutterActivity() {

    private val activityJob = Job()
    private val activityScope = CoroutineScope(Dispatchers.Main + activityJob)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> runOffMainThread(result) {
                    NativeScanner.getInstalledApps(applicationContext)
                }

                "computeApkSha256" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName == null) {
                        result.error("ARG_ERROR", "packageName manjka", null)
                        return@setMethodCallHandler
                    }
                    runOffMainThread(result) {
                        NativeScanner.computeApkSha256(applicationContext, packageName)
                    }
                }

                "getSystemSecuritySnapshot" -> runOffMainThread(result) {
                    NativeScanner.getSystemSecuritySnapshot(applicationContext)
                }

                "getUsageStats" -> {
                    val days = call.argument<Int>("days") ?: 7
                    runOffMainThread(result) {
                        NativeScanner.getUsageStats(applicationContext, days)
                    }
                }

                "getBatterySnapshot" -> runOffMainThread(result) {
                    NativeScanner.getBatterySnapshot(applicationContext)
                }

                "captureBatterySampleNow" -> runOffMainThread(result) {
                    val sample = NativeScanner.getBatterySnapshot(applicationContext)
                    NativeScanner.appendBatterySample(applicationContext, sample)
                    sample
                }

                "readBatteryHistory" -> {
                    val since = (call.argument<Number>("sinceEpochMs") ?: 0L).toLong()
                    runOffMainThread(result) {
                        NativeScanner.readBatteryHistory(applicationContext, since)
                    }
                }

                "scheduleBatterySampling" -> {
                    scheduleBatterySampling()
                    result.success(null)
                }

                "cancelBatterySampling" -> {
                    WorkManager.getInstance(applicationContext).cancelUniqueWork(BATTERY_WORK_NAME)
                    result.success(null)
                }

                "openSpecialSetting" -> {
                    val target = call.argument<String>("target") ?: ""
                    NativeScanner.openSpecialSetting(applicationContext, target)
                    result.success(null)
                }

                "openAppDetailsSettings" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName == null) {
                        result.error("ARG_ERROR", "packageName manjka", null)
                    } else {
                        NativeScanner.openAppDetailsSettings(applicationContext, packageName)
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleBatterySampling() {
        val request = PeriodicWorkRequestBuilder<BatterySamplerWorker>(15, TimeUnit.MINUTES).build()
        WorkManager.getInstance(applicationContext).enqueueUniquePeriodicWork(
            BATTERY_WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request,
        )
    }

    /**
     * Poganja (potencialno počasen, IO-vezan) native klic na ozadnjem niti
     * in vrne rezultat MethodChannel-u na glavni niti, kot to Flutter
     * zahteva.
     */
    private fun <T> runOffMainThread(result: MethodChannel.Result, block: suspend () -> T) {
        activityScope.launch {
            val value = try {
                withContext(Dispatchers.IO) { block() }
            } catch (t: Throwable) {
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", t.message, null)
                }
                return@launch
            }
            result.success(value)
        }
    }

    override fun onDestroy() {
        activityJob.cancel()
        super.onDestroy()
    }
}
