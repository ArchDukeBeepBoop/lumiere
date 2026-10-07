plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "app.lumiere.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.lumiere.android"
        minSdk = 26
        targetSdk = 36
        // Minutes since 2026, so every build is newer than the one before —
        // whichever session or copy of the code made it. Commit counts were
        // tried first and two sessions' counts drifted apart: the phone held 24
        // and would not take 17.
        val minutes = ((System.currentTimeMillis() / 1000 - 1767225600L) / 60).toInt()
        versionCode = minutes
        versionName = "1.${minutes / 1440}.${minutes % 1440}"
    }
    signingConfigs {
        // The same key the first installs were signed with, so a release
        // replaces them in place — sign-in, settings and downloads kept.
        create("home") {
            storeFile = file(System.getProperty("user.home") + "/.android/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("home")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true; buildConfig = true }
    // Phone and TV as before, and Meta Quest: the TV layout in a Horizon OS
    // window (docs/quest/PLAN.md, v0.5). Its own id, so it never takes, or
    // is taken by, the phone's update from the Mac.
    flavorDimensions += "device"
    productFlavors {
        create("standard") {
            dimension = "device"
            isDefault = true
            buildConfigField("boolean", "QUEST", "false")
        }
        create("quest") {
            dimension = "device"
            applicationIdSuffix = ".quest"
            versionNameSuffix = "-quest"
            buildConfigField("boolean", "QUEST", "true")
        }
    }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.03")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.6")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.coil-kt:coil-compose:2.7.0")
    val media3 = "1.8.0"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-ui:$media3")
    implementation("androidx.media3:media3-datasource-okhttp:$media3")
    implementation("androidx.media3:media3-session:$media3")
    implementation("androidx.tvprovider:tvprovider:1.1.0")
    implementation("androidx.tv:tv-material:1.0.0")
    implementation("io.github.peerless2012:ass-media:0.3.0-rc03")
    implementation("androidx.profileinstaller:profileinstaller:1.3.1")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}
