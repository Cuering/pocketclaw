plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.pocketclaw.pocketclaw"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.pocketclaw.pocketclaw"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // ABI filter: restrict native libs to arm64-v8a only.
        // flutter_gemma's .litertlm engine ships arm64-v8a prebuilts only.
        // Including other ABIs would create APKs that crash at model load on
        // x86_64 emulators or armeabi-v7a (very old) devices.
        // Apple Silicon Mac emulators ARE arm64-v8a, so we're fine.
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // R8 strips MediaPipe / protobuf classes referenced reflectively
            // from native code (flutter_gemma's transitive dependency).
            // proguard-rules.pro contains the keep rules. We use the
            // default Android optimized config + ours.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        jniLibs {
            excludes.addAll(
                listOf(
                    // Other architectures — we ship arm64-v8a only.
                    "**/x86_64/**",
                    "**/x86/**",
                    "**/armeabi-v7a/**",
                    "**/armeabi/**",
                    // Image generation runtime — flutter_gemma bundles this but
                    // we never generate images, only consume them as input to
                    // Gemma's vision encoder. Saves ~24 MB.
                    "**/libimagegenerator_gpu.so",
                    "**/libmediapipe_tasks_vision_image_generator_jni.so",
                    // WebGPU runtime — for browsers, useless on Android where
                    // we use OpenCL acceleration. Saves ~9 MB.
                    "**/libLiteRtWebGpuAccelerator.so",
                    "**/libLiteRtTopKWebGpuSampler.so"
                )
            )
        }
    }
}

flutter {
    source = "../.."
}
