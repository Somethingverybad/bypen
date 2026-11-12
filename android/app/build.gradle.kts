import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Номер сборки — число коммитов, как у остальных проектов WYX.
fun gitCount(): Int = try {
    val p = ProcessBuilder("git", "rev-list", "--count", "HEAD").directory(rootDir).start()
    p.inputStream.bufferedReader().readText().trim().toInt()
} catch (e: Exception) { 1 }

// Ключ выпуска: ~/bypen-keys/signing.properties (storeFile, storePassword, keyAlias, keyPassword).
val signing = Properties().apply {
    val f = File(System.getProperty("user.home"), "bypen-keys/signing.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.hyax.bypen"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.hyax.bypen"
        minSdk = 29
        targetSdk = 36
        versionCode = gitCount()
        versionName = "0.1.${gitCount()}"
    }
    // Ядро Xray — ~40 МБ на архитектуру, поэтому APK на каждую отдельно (arm64 — почти все телефоны).
    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = false
        }
    }
    signingConfigs {
        if (signing.getProperty("storeFile") != null) {
            create("release") {
                storeFile = File(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    packaging {
        jniLibs { useLegacyPackaging = false }
        resources { excludes += setOf("META-INF/versions/9/OSGI-INF/MANIFEST.MF", "META-INF/LICENSE*", "META-INF/NOTICE*", "META-INF/*.kotlin_module") }
    }
}

dependencies {
    implementation(files("libs/libXray.aar"))
    implementation(files("libs/hev-socks5-tunnel.aar"))
    val bom = platform("androidx.compose:compose-bom:2025.06.01")
    implementation(bom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.1")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.bouncycastle:bcprov-jdk18on:1.79")
}
