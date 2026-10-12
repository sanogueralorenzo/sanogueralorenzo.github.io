plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val steam = rootProject.file("../androidsteam")

android {
    namespace = "com.sanogueralorenzo.amarchy"
    compileSdk = 36
    ndkVersion = "29.0.14206865"
    defaultConfig {
        applicationId = "com.sanogueralorenzo.amarchy"
        minSdk = 36
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += "arm64-v8a" }
        externalNativeBuild.cmake.arguments += "-DDECK_DEPS=${layout.buildDirectory.dir("display-deps").get().asFile}"
        externalNativeBuild.cmake.arguments += "-DANDROID_PLATFORM=android-35"
        externalNativeBuild.cmake.targets += "amarchy-display"
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    packaging.jniLibs.useLegacyPackaging = true
    androidResources.noCompress += "gzip"
    externalNativeBuild.cmake { path = rootProject.file("native/CMakeLists.txt"); version = "3.22.1" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    sourceSets["main"].jniLibs.srcDir(layout.buildDirectory.dir("proot"))
    sourceSets["main"].jniLibs.srcDir(layout.buildDirectory.dir("linux"))
    sourceSets["debug"].jniLibs.srcDir(layout.buildDirectory.dir("linux-probe"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("environment"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("licenses"))
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

val buildProot by tasks.registering(Exec::class) {
    inputs.files(fileTree(steam.resolve("native/proot")))
    inputs.property("ndkVersion", android.ndkVersion.orEmpty())
    outputs.dir(layout.buildDirectory.dir("proot/arm64-v8a"))
    environment("NDK", File(android.sdkDirectory, "ndk/${android.ndkVersion}"))
    commandLine("bash", steam.resolve("native/proot/build.sh"), layout.buildDirectory.dir("proot/arm64-v8a").get().asFile)
}
val prepareDisplay by tasks.registering(Exec::class) {
    inputs.files(rootProject.file("native/dependencies.sh"), rootProject.file("native/source.env"))
    outputs.dir(layout.buildDirectory.dir("display-deps"))
    environment("NDK", File(android.sdkDirectory, "ndk/${android.ndkVersion}"))
    commandLine("bash", rootProject.file("native/dependencies.sh"), layout.buildDirectory.dir("display-deps").get().asFile)
}
val assembleEnvironment by tasks.registering(Exec::class) {
    inputs.files(rootProject.file("runtime/build.py"), rootProject.file("runtime/packages.lock.json"), rootProject.file("runtime/omarchy.lock.json"))
    outputs.files(layout.buildDirectory.file("environment/environment.tar.gzip"), layout.buildDirectory.file("environment/environment.json"))
    commandLine("python3", rootProject.file("runtime/build.py"), layout.buildDirectory.dir("environment").get().asFile)
}
val packageLicenses by tasks.registering(Sync::class) {
    from(rootProject.file("LICENSE"), rootProject.file("THIRD_PARTY.md"))
    from(steam.resolve("licenses")) {
        include("Apache-2.0.txt", "GCC-RUNTIME-LIBRARY-EXCEPTION", "LGPL-3.0.txt", "LIBFFI-LICENSE",
            "LINUX-DMABUF-COPYING", "PROOT-COPYING", "WAYLAND-COPYING", "XDG-SHELL-COPYING", "XKB-DATA-COPYRIGHT", "XZ-COPYING")
        into("licenses")
    }
    into(layout.buildDirectory.dir("licenses"))
}
val compileLinuxAdapter by tasks.registering(Exec::class) {
    dependsOn(assembleEnvironment)
    inputs.files(rootProject.file("native/linux.py"), rootProject.file("native/software_drm.c"), rootProject.file("native/egl_probe.c"), rootProject.file("runtime/packages.lock.json"))
    inputs.property("ndkVersion", android.ndkVersion.orEmpty())
    outputs.file(layout.buildDirectory.file("linux/arm64-v8a/libamarchy-software-drm.so"))
    outputs.file(layout.buildDirectory.file("linux-probe/arm64-v8a/libamarchy-egl-probe.so"))
    environment("NDK", File(android.sdkDirectory, "ndk/${android.ndkVersion}"))
    commandLine("python3", rootProject.file("native/linux.py"), layout.buildDirectory.dir("linux/arm64-v8a").get().asFile)
}
val buildAquamarine by tasks.registering(Exec::class) {
    dependsOn(assembleEnvironment)
    inputs.files(rootProject.fileTree("native/aquamarine"), rootProject.file("runtime/packages.lock.json"))
    inputs.property("ndkVersion", android.ndkVersion.orEmpty())
    outputs.file(layout.buildDirectory.file("linux/arm64-v8a/libamarchy-aquamarine.so"))
    environment("NDK", File(android.sdkDirectory, "ndk/${android.ndkVersion}"))
    commandLine("python3", rootProject.file("native/aquamarine/build.py"), layout.buildDirectory.file("linux/arm64-v8a/libamarchy-aquamarine.so").get().asFile)
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(buildProot, prepareDisplay, compileLinuxAdapter, buildAquamarine, packageLicenses) }
tasks.matching { it.name.startsWith("configureCMake") }.configureEach { dependsOn(prepareDisplay) }

dependencies {
    implementation("org.apache.commons:commons-compress:1.28.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}
