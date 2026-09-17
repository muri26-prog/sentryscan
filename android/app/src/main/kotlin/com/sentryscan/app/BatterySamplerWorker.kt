package com.sentryscan.app

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * WorkManager periodično (najmanj vsakih 15 minut - to je omejitev
 * Android OS-a za PeriodicWorkRequest, ne naša izbira) zapiše en vzorec
 * stanja baterije v `battery_history.jsonl`. Dart stran nato to zgodovino
 * prebere preko `readBatteryHistory` in izračuna hitrost praznjenja
 * (%/uro), poveže padce z obdobji zaslon-vklopljen (iz UsageStats) itd.
 */
class BatterySamplerWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        return try {
            val sample = NativeScanner.getBatterySnapshot(applicationContext)
            NativeScanner.appendBatterySample(applicationContext, sample)
            Result.success()
        } catch (t: Throwable) {
            Result.retry()
        }
    }
}
