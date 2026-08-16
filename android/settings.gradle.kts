pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // 8.11.1 = الحدّ الأدنى الذي يفرضه Flutter 3.47. نبقى داخل 8.x عمداً:
    // Flutter يحذّر أن AGP 9 يقرأ الواجهة الجديدة وحدها فتنكسر إضافته.
    id("com.android.application") version "8.11.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version "4.4.1" apply false
    // END: FlutterFire Configuration
    // 2.2.20 = ثالث وآخر حدّ تفرضه إضافة Flutter 3.47 (بعد Gradle وAGP).
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
