# Platformu konfigurācija (jāieliek projekta saknē — šīs mapes nebija augšupielādētas)

## Android
`android/app/src/main/AndroidManifest.xml` — pievieno **pirms** `<application>` (debug/profile to jau saņem, release nē):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
```
Īsts release paraksts (`android/app/build.gradle.kts`):
```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    namespace = "lv.tavs.locsand"          // nomaini uz savu domēnu
    defaultConfig { applicationId = "lv.tavs.locsand" }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    buildTypes {
        release { signingConfig = signingConfigs.getByName("release") }
    }
}
```
Atslēgu izveido ar `keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`.
`key.properties` un `*.jks` **nedrīkst** nonākt Git (pieliec `.gitignore`).
(Ja gradle fails ir Groovy, nevis Kotlin, sintakse nedaudz atšķiras.)

## iOS
`ios/Runner/Info.plist`:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>LocSand izmanto lokālo tīklu, lai atrastu tuvumā esošas ierīces un nosūtītu tām ziņas un failus.</string>
```
Piezīme: UDP broadcast/multicast uz iOS var prasīt arī `com.apple.developer.networking.multicast`
entitlement (jāpieprasa Apple). To vajag pārbaudīt uz īstas ierīces — es to no šejienes nevaru apstiprināt.

## macOS
Gan `macos/Runner/Release.entitlements`, gan `DebugProfile.entitlements`:
```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.network.server</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.files.downloads.read-write</key><true/>
```
(`downloads` vajag, jo noklusējuma saņemšanas mape ir Downloads.)

## Web
Aplikācija izmanto `dart:io` sockets (`RawDatagramSocket`, `SecureSocket`) — Flutter Web tos neatbalsta.
Vai nu izdzēs `web/` mapi un README norādi, ka Web netiek atbalstīts, vai pārraksti transportu.

## pubspec.yaml
```
flutter pub add crypto          # jauns: SHA-256 ierīces ID un handshake
```
Nomaini `description:` no "A new Flutter project" uz īstu aprakstu. `basic_utils`, `path_provider`,
`file_picker`, `toml` jau tiek lietoti; `flutter_test` ir dev dependency.

## Windows / Linux
Pirmajā palaišanā Windows Firewall jautās par piekļuvi privātajam tīklam — jāatļauj. Ja ierīces neredz
viena otru, pārbaudi: tas pats LAN, nav "guest Wi-Fi" izolācijas, UDP un TCP porti (no `assets/config.toml`) nav bloķēti.
