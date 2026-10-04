plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.sanogueralorenzo.androiddeck"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    defaultConfig {
        applicationId = "com.sanogueralorenzo.androiddeck"
        minSdk = 36
        // Direct exec is blocked at 36; the APK-packaged PRoot loader runs the guest.
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += "arm64-v8a" }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
    packaging { jniLibs.useLegacyPackaging = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets["debug"].jniLibs.srcDir(layout.buildDirectory.dir("executionProbe"))
    sourceSets["main"].jniLibs.srcDir(layout.buildDirectory.dir("proot"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("licenseAssets"))
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

// Only debug APKs contain this execution-policy test, never release APKs.
val compileExecutionProbe by tasks.registering(Exec::class) {
    val host = if (System.getProperty("os.name").startsWith("Mac")) "darwin-x86_64" else "linux-x86_64"
    val compiler = File(android.sdkDirectory, "ndk/${android.ndkVersion}/toolchains/llvm/prebuilt/$host/bin/aarch64-linux-android35-clang")
    val source = file("src/debug/native/execution_probe.c")
    val output = layout.buildDirectory.file("executionProbe/arm64-v8a/libexecution-probe.so")
    inputs.files(source, compiler)
    outputs.file(output)
    doFirst { output.get().asFile.parentFile.mkdirs() }
    commandLine(compiler, "-O2", "-Wl,-z,max-page-size=16384", source, "-o", output.get().asFile)
}
tasks.matching { it.name == "preDebugBuild" }.configureEach { dependsOn(compileExecutionProbe) }

val buildProot by tasks.registering(Exec::class) {
    inputs.files(rootProject.fileTree("native/proot"))
    inputs.property("ndkVersion", android.ndkVersion.orEmpty())
    val output = layout.buildDirectory.dir("proot/arm64-v8a")
    outputs.dir(output)
    environment("NDK", File(android.sdkDirectory, "ndk/${android.ndkVersion}"))
    commandLine("bash", rootProject.file("native/proot/build.sh"), output.get().asFile)
}
val packageLicenses by tasks.registering(Sync::class) {
    from(rootProject.file("LICENSE"), rootProject.file("THIRD_PARTY.md"))
    from(rootProject.file("licenses")) { into("licenses") }
    into(layout.buildDirectory.dir("licenseAssets"))
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(buildProot, packageLicenses) }

dependencies {
    implementation("org.apache.commons:commons-compress:1.28.0")
    implementation("org.tukaani:xz:1.12")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}
