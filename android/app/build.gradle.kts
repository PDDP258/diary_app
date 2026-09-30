plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.diary_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.diary_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 项目基线 Android 8.0 (API 26)：通知渠道、前台服务、桌面小组件（自绘 RemoteViews）
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // 版本号统一以 pubspec.yaml 为准（flutter.versionCode/versionName 来自 local.properties）
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // WorkManager：每日后台刷新课表小组件 + 续排课前提醒窗口。
    // 用它而不是广播接收器里的 goAsync()——后者只有 ~10s 执行窗口，
    // 而起 Flutter 引擎跑 Dart 大概率超时被杀。
    // 版本与之前 glance_widget 传递依赖过的保持一致，确定能解析。
    implementation("androidx.work:work-runtime-ktx:2.11.2")
}

flutter {
    source = "../.."
}
