plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.sanogueralorenzo.androidsteam"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    defaultConfig {
        applicationId = "com.sanogueralorenzo.androidsteam"
        minSdk = 36
        // Direct exec is blocked at 36; the APK-packaged PRoot loader runs the guest.
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        ndk { abiFilters += "arm64-v8a" }
        externalNativeBuild.cmake.arguments += "-DDECK_DEPS=${layout.buildDirectory.dir("display-deps").get().asFile}"
        externalNativeBuild.cmake.targets += listOf("deck-display", "main_hook", "hook_impl")
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    packaging {
        jniLibs.useLegacyPackaging = true
        // The fixed custom-driver path uses neither file redirection nor GPU mapping.
        jniLibs.excludes += setOf("**/libfile_redirect_hook.so", "**/libgsl_alloc_hook.so")
    }
    externalNativeBuild.cmake {
        path = rootProject.file("native/display/CMakeLists.txt")
        version = "3.22.1"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    sourceSets["main"].jniLibs.srcDir(layout.buildDirectory.dir("proot"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("licenseAssets"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("sessionAssets"))
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

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
val prepareDisplayDependencies by tasks.registering(Exec::class) {
    inputs.files(rootProject.file("native/display/dependencies.sh"), rootProject.file("native/display/source.env"))
    inputs.property("ndkVersion", android.ndkVersion.orEmpty())
    val output = layout.buildDirectory.dir("display-deps")
    outputs.dir(output)
    environment("NDK", File(android.sdkDirectory, "ndk/${android.ndkVersion}"))
    commandLine("bash", rootProject.file("native/display/dependencies.sh"), output.get().asFile)
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(buildProot, packageLicenses, prepareDisplayDependencies) }
tasks.matching { it.name.startsWith("configureCMake") }.configureEach { dependsOn(prepareDisplayDependencies) }
val buildSessionAdapters by tasks.registering(Exec::class) {
    inputs.files(rootProject.fileTree("native/session"), rootProject.file("native/runtime/mesa/packages.tsv"), rootProject.file("native/display/linux.sh"))
    inputs.property("ndkVersion", android.ndkVersion.orEmpty())
    val output = layout.buildDirectory.dir("linuxDisplay")
    outputs.files(output.map { it.file("libxbox-evdev.so") }, output.map { it.file("libxbox-udev.so") }, output.map { it.file("libdeck-drm.so") }, output.map { it.file("libdeck-robust.so") }, output.map { it.file("libdeck-ports.so") }, output.map { it.file("libsteam-wine-memory.so") }, output.map { it.file("steam-socket-peer") }, output.map { it.file("libsteam-ui-pipe.so") })
    environment("NDK", File(android.sdkDirectory, "ndk/${android.ndkVersion}"))
    commandLine("bash", rootProject.file("native/display/linux.sh"), output.get().asFile)
}
val packageSessionComponents by tasks.registering(Exec::class) {
    dependsOn(buildSessionAdapters)
    inputs.files(rootProject.file("native/session/packages.sh"))
    val output = layout.buildDirectory.dir("sessionAssets")
    inputs.files(layout.buildDirectory.file("linuxDisplay/libxbox-udev.so"), layout.buildDirectory.file("linuxDisplay/libxbox-evdev.so"), layout.buildDirectory.file("linuxDisplay/libdeck-drm.so"), layout.buildDirectory.file("linuxDisplay/libdeck-robust.so"), layout.buildDirectory.file("linuxDisplay/libdeck-ports.so"), layout.buildDirectory.file("linuxDisplay/libsteam-wine-memory.so"), layout.buildDirectory.file("linuxDisplay/steam-socket-peer"), layout.buildDirectory.file("linuxDisplay/libsteam-ui-pipe.so"))
    outputs.file(output.map { it.file("session-components.tar.xz") })
    commandLine("bash", rootProject.file("native/session/packages.sh"), output.get().asFile, layout.buildDirectory.dir("linuxDisplay").get().asFile)
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(packageSessionComponents) }

dependencies {
    implementation("org.apache.commons:commons-compress:1.28.0")
    implementation("org.tukaani:xz:1.12")
}
