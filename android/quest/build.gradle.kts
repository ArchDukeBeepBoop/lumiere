plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Lumiere on Meta Quest, in space: the same app as the phone and TV, its
// window placed in your room by Meta Spatial SDK (docs/quest/PLAN.md, Phase 2).
// Its own id while it is proven on the headset, so the 2D build (:app's quest
// flavor) can stay installed beside it.
android {
    namespace = "app.lumiere.android.spatial"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.lumiere.android.spatial"
        minSdk = 34
        targetSdk = 34
        val minutes = ((System.currentTimeMillis() / 1000 - 1767225600L) / 60).toInt()
        versionCode = minutes
        versionName = "1.${minutes / 1440}.${minutes % 1440}-spatial"
        // Quest 3 and 3S are arm64; other processors' libraries would only add weight.
        ndk { abiFilters += "arm64-v8a" }
    }
    signingConfigs {
        create("home") {
            storeFile = file(System.getProperty("user.home") + "/.android/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("home")
        }
    }
    packaging { resources.excludes.add("META-INF/LICENSE") }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true; buildConfig = true }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    implementation(project(":screens"))
    val spatial = "0.14.0"
    implementation("com.meta.spatial:meta-spatial-sdk:$spatial")
    implementation("com.meta.spatial:meta-spatial-sdk-toolkit:$spatial")
    implementation("com.meta.spatial:meta-spatial-sdk-vr:$spatial")

    testImplementation("junit:junit:4.13.2")
}
