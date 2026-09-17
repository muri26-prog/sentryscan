# SentryScan

Lokalni, sideload Android pregledovalnik za zaznavo morebitne vohunske/nadzorne
programske opreme (stalkerware/spyware), sumljivih dovoljenj/nastavitev ter
analizo vzrokov praznjenja baterije. Zgrajen v Flutterju (Dart UI) z Kotlin
native slojem za dostop do Android sistemskih API-jev.

## Arhitektura na kratko

```
lib/                     Dart/Flutter UI + orkestracija
  models/                Podatkovni razredi (AppInfo, RiskFinding, ...)
  services/
    native_bridge.dart       Tanek MethodChannel ovoj
    heuristics_engine.dart   VSA "je to sumljivo?" logika (edino mesto)
    virustotal_service.dart  VirusTotal API v3 klient (samo SHA-256, rate-limited)
    battery_analysis_service.dart  Analiza praznjenja iz zgodovine + UsageStats
    storage_service.dart     sqflite (VT cache, zgodovina), secure storage (API ključ)
    scan_service.dart        Orkestrator: bridge -> heuristika -> (VT) -> report
  screens/               Zasloni (Home, Scan, Report, App detail, Battery, Settings, Permissions)

android/app/src/main/kotlin/com/sentryscan/app/
  NativeScanner.kt       SUROVA dejstva o sistemu/aplikacijah (PackageManager,
                          Settings.Secure, DevicePolicyManager, UsageStatsManager,
                          BatteryManager) - namenoma BREZ ocene tveganja
  RootDetector.kt        Heuristična zaznava root dostopa
  BatterySamplerWorker.kt WorkManager periodično (~15 min) beleženje baterije
  MainActivity.kt        MethodChannel "com.sentryscan.app/native"
```

Načelo ločitve odgovornosti: **Kotlin bere samo surova dejstva. Vsa presoja
tveganja je v `lib/services/heuristics_engine.dart`.** Če želiš spremeniti
pravila (dodati/omiliti/zaostriti najdbo), moraš urejati SAMO ta Dart
datoteko - Android koda ostane nedotaknjena.

## Kaj aplikacija dejansko zna preveriti (in kaj ne)

Brez root dostopa in brez objave na Google Play (sideload) je to zgornja meja
tega, kar je Android dovoljeno tretji aplikaciji:

**Zmore:**
- Seznam VSEH nameščenih aplikacij (`QUERY_ALL_PACKAGES`), njihova dovoljenja,
  vir namestitve (Play Store vs. sideload), ali imajo ikono v meniju.
- Kdo ima omogočeno dostopnostno storitev, dostop do obvestil, pravice
  skrbnika naprave (device admin) - pogosti vektorji stalkerware.
- Root heuristika (su binarniki, test-keys, znane root-management aplikacije).
- ADB/Developer options, šifriranje shrambe, zaklep zaslona, aktivna VPN/proxy.
- Natančen upad % baterije skozi čas + katera aplikacija ima največ časa v
  ospredju (UsageStats) + katere aplikacije so izvzete iz varčevanja baterije.
- VirusTotal preverjanje SHA-256 hasha APK datoteke (na zahtevo, za označene
  aplikacije) - potrebuje tvoj brezplačni API ključ.

**NE zmore (poštene omejitve Android varnostnega modela, ne bug):**
- Natančne porabe baterije PO APLIKACIJI (ta API - `BatteryStats`/
  `BatteryUsageStats` - je rezerviran za sistemske/privilegirane aplikacije).
  Namesto tega uporabljamo najboljše posredne kazalnike (glej zgoraj).
- Branja tekočih storitev DRUGIH aplikacij (`getRunningServices` od Androida 5+
  vrača le lastne storitve klicatelja).
- Popolnoma zanesljive zaznave sofisticiranega, dobro prikritega malwarea
  (to zahteva pravo protivirusno bazo/sandbox analizo - zato je vgrajena
  VirusTotal integracija, ne pa lastni signature engine).
- 100% zanesljive root detekcije (napredni root skriva sam sebe - heuristika
  kombinira več šibkih signalov, kar je enak pristop kot ga uporabljajo
  uveljavljene knjižnice, a ni matematično dokazljivo).

## Najlažja pot do .apk: GitHub Actions (brez namestitve česarkoli lokalno)

Projekt vsebuje pripravljen workflow `.github/workflows/build-apk.yml`, ki
zgradi .apk V OBLAKU (GitHub-ovi strežniki že imajo Android SDK/Flutter) - na
svojem računalniku ne rabiš namestiti NIČESAR, samo brskalnik.

1. Ustvari brezplačen račun na [github.com](https://github.com), če ga še nimaš.
2. Ustvari nov (lahko zaseben) repozitorij, npr. "sentryscan".
3. Naloži vso vsebino razpakirane mape `sentryscan/` vanj - najlažje prek
   spletnega vmesnika: na strani repozitorija **Add file → Upload files**,
   povleci vanj vse datoteke/mape iz razpakiranega `sentryscan.zip`.
4. Pojdi na zavihek **Actions** v repozitoriju → izberi "Build APK" → **Run
   workflow** (zeleni gumb) → počakaj ~5-8 minut, da gradnja (zeleni kljukica)
   uspe.
5. Klikni na zaključen "run" → na dnu strani pod **Artifacts** prenesi
   `sentryscan-apk` (to je .zip, znotraj je `app-release.apk`).
6. Datoteko `app-release.apk` prenesi na telefon (Google Drive, e-pošta samemu
   sebi, USB ...) in jo odpri - Android bo vprašal za dovoljenje "namesti iz
   neznanega vira", kar potrdi.

Če raje delaš prek `git` namesto spletnega nalaganja: `git init`, `git add .`,
`git commit -m "init"`, ustvari repo na GitHub in `git push` - workflow se
sproži samodejno ob push-u na `main`.

## Alternativa: gradnja na svojem računalniku

## Predpogoji za gradnjo

- Flutter SDK (stable channel; razvito in preverjeno s **Flutter 3.47.4 /
  Dart 3.13.3** - `flutter --version`)
- Android Studio ali samostojen Android SDK: **compileSdk/targetSdk 36**,
  JDK 17 (Android Studio ju namesti/posodobi samodejno ob prvem odprtju)
- Android telefon z **Android 8.0 (API 26)** ali novejšim, z omogočenim
  USB razhroščevanjem (za sideload prek `adb install`)

## Gradnja in namestitev (sideload)

```bash
flutter pub get
flutter build apk --release      # ali --debug za hitrejšo iteracijo brez optimizacije
adb install build/app/outputs/flutter-apk/app-release.apk
```

Release build je (namenoma, za osebno sideload uporabo) podpisan z debug
keystore, glej `android/app/build.gradle`. Za resnično distribucijo zamenjaj
`signingConfigs.debug` z lastnim keystore-om.

Če `android/local.properties` ne obstaja, jo Android Studio/`flutter` orodje
ustvari samodejno ob prvem odprtju/gradnji (vsebuje poti do tvojega Flutter
in Android SDK - namerno ni v repozitoriju, ker je odvisna od tvojega stroja).

## Po namestitvi: nastavi dovoljenja

Odpri aplikacijo -> **"Preveri dovoljenja"** na domačem zaslonu in dovoli:
1. **Usage access** (statistika uporabe) - potrebno za analizo baterije in
   zaznavo "skritih, nenehno aktivnih" aplikacij.
2. **Obvestila** - za opozorila o zaključenih pregledih/kritičnih najdbah.
3. **Izjema od varčevanja baterije (za SentryScan samo)** - da periodično
   beleženje zanesljivo teče tudi z ugasnjenim zaslonom.

`QUERY_ALL_PACKAGES` in osnovna sistemska dejstva delujejo takoj po namestitvi
brez dodatnih korakov (ker gre za sideload, ne za Play Store distribucijo).

## VirusTotal (neobvezno, a priporočeno)

1. Ustvari brezplačen račun na [virustotal.com](https://www.virustotal.com) in
   pridobi API ključ (Nastavitve v aplikaciji -> "Pridobi ključ").
2. V SentryScan -> Nastavitve: vklopi "Omogoči VirusTotal poizvedbe" in prilepi
   ključ.
3. Po pregledu, na zaslonu z rezultati, pritisni "Preveri N aplikacij na
   VirusTotal" - preveri SAMO tiste, ki jih je lokalna heuristika že označila
   (javni API dovoljuje ~4 zahtevke/minuto, zato preverjanje VSEH nameščenih
   aplikacij ne bi bilo praktično niti smiselno).

Pošlje se izključno SHA-256 hash APK datoteke, nikoli njena vsebina.

## Analiza baterije - kako uporabiti

1. Battery zaslon -> vklopi "Periodično beleženje v ozadju".
2. Pusti vklopljeno vsaj 24-48h (idealno prek enega celotnega cikla
   polnjenja) za zanesljivo oceno hitrosti praznjenja.
3. Vrni se na zaslon - prikaže graf nivoja baterije, %/uro hitrost praznjenja
   in seznam najverjetnejših "osumljencev" (čas v ospredju, izjeme od
   varčevanja, standby stanje).

## Stanje preverjanja v tem razvojnem okolju

Ta projekt je bil pripravljen v peskovniku brez grafičnega vmesnika/telefona
in z omrežno politiko, ki blokira `dl.google.com` (Android SDK/Maven), zato
**Kotlin/Android stran ni bilo mogoče dejansko Gradle zgraditi tukaj** - koda
je bila skrbno ročno pregledana glede pravilnosti API klicev, a priporočam,
da ob prvi gradnji na svojem računalniku pozorno prebereš morebitne opozorilne
izpise iz Gradle/Kotlin prevajalnika.

Dart/Flutter stran JE bila preverjena v tem okolju:
- `flutter pub get` uspešno razreši vse odvisnosti,
- `flutter analyze` ne javi nobenih napak ali opozoril (0 issues).

Iz istega razloga tudi `.github/workflows/build-apk.yml` ni bilo mogoče
dejansko pognati od tu (za to bi rabil tvoj GitHub repozitorij) - workflow je
sestavljen iz standardnih, uveljavljenih GitHub Actions (`subosito/flutter-action`,
`actions/setup-java`), a prvi zagon vseeno preveri v praksi.

## Zasebnost

Vsi podatki (seznam aplikacij, zgodovina baterije, ocene tveganja) ostanejo
lokalno na napravi (SQLite + secure storage). Edini odhodni omrežni klic je
izrecno sprožena VirusTotal poizvedba za en SHA-256 hash - nič drugega se
nikamor ne pošilja.

## Omejitev odgovornosti

Najdbe so **indikatorji tveganja**, ne dokončen dokaz okužbe ali nadzora.
Kritične/visoke najdbe preveri ročno (npr. poglej podrobnosti aplikacije,
preveri, ali jo prepoznaš) preden ukrepaš (odstranitev aplikacije, tovarniška
ponastavitev). Če sumiš na resnično nasilje v družini/zalezovanje prek
telefona, upoštevaj tudi previdnostne ukrepe glede varnosti pri sami uporabi
te aplikacije (napadalec z dostopom do telefona lahko vidi, da si jo
namestil/a) in po potrebi poišči pomoč specializirane organizacije, ne le
tehnično rešitev.
