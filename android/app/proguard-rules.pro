# WorkManager + Kotlin coroutines uporabljajo refleksijo za Worker razrede -
# obdrži jih, sicer periodično vzorčenje baterije v release buildu tiho odpove.
-keep class com.sentryscan.app.** { *; }
-keep class androidx.work.** { *; }
