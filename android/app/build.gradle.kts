plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.motopulse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.motopulse"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // NOTE: No abiFilters here — applied per build type below
    }

    packaging {
        jniLibs {
            // Required for 16KB page-size compatibility on Android 15+
            useLegacyPackaging = false
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Release: ARM only — strips x86_64 (emulator-only, causes 16KB warning)
            ndk {
                abiFilters += listOf("arm64-v8a", "armeabi-v7a")
            }
        }
        // debug: no abiFilters — allows x86_64 so the emulator works
    }
}

// Also exclude x86_64 JNI libs from AARs in release only (ML Kit / Firebase bypass abiFilters)
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.add("lib/x86_64/**")
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools.desugar_jdk_libs:2.1.4")
}
