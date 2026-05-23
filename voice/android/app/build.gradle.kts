plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.metro)
}

val voiceEngineDir = rootProject.file("../engine")
val generatedRustJniLibsDir = layout.buildDirectory.dir("generated/rustJniLibs")
val generatedRustJniLibsFile = layout.buildDirectory.asFile.get().resolve("generated/rustJniLibs")

android {
    namespace = "com.sanogueralorenzo.voice"
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        applicationId = "com.sanogueralorenzo.voice"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    sourceSets {
        named("main") {
            jniLibs.setSrcDirs(listOf(generatedRustJniLibsFile))
        }
    }
}

val buildVoiceEngineHost by tasks.registering(Exec::class) {
    workingDir = voiceEngineDir
    commandLine("cargo", "build", "--manifest-path", voiceEngineDir.resolve("Cargo.toml").absolutePath)
    inputs.dir(voiceEngineDir.resolve("src"))
    inputs.file(voiceEngineDir.resolve("Cargo.toml"))
    doNotTrackState("Cargo owns its incremental target directory.")
}

val buildVoiceEngineAndroid by tasks.registering(Exec::class) {
    workingDir = voiceEngineDir
    commandLine(
        "/bin/sh",
        voiceEngineDir.resolve("scripts/build-android.sh").absolutePath,
        generatedRustJniLibsDir.get().asFile.absolutePath
    )
    inputs.dir(voiceEngineDir.resolve("src"))
    inputs.file(voiceEngineDir.resolve("Cargo.toml"))
    inputs.file(voiceEngineDir.resolve("scripts/build-android.sh"))
    outputs.dir(generatedRustJniLibsDir)
}

tasks.withType<Test>().configureEach {
    dependsOn(buildVoiceEngineHost)
    systemProperty("java.library.path", voiceEngineDir.resolve("target/debug").absolutePath)
    systemProperty("voice.engine.fixtures.dir", voiceEngineDir.resolve("fixtures").absolutePath)
    inputs.dir(voiceEngineDir.resolve("fixtures"))
}

tasks.matching { task ->
    task.name.startsWith("merge") && task.name.endsWith("JniLibFolders")
}.configureEach {
    dependsOn(buildVoiceEngineAndroid)
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.litertlm.android)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.mavericks)
    implementation(libs.mavericks.compose)
    implementation(libs.moonshine.voice)
    testImplementation(libs.junit)
    testImplementation("org.json:json:20240303")
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
