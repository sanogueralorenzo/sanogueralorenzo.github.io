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
    sourceSets["debug"].jniLibs.srcDir(layout.buildDirectory.dir("executionProbe"))
    sourceSets["debug"].jniLibs.srcDir(layout.buildDirectory.dir("linuxDisplay/probe"))
    sourceSets["main"].jniLibs.srcDir(layout.buildDirectory.dir("proot"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("licenseAssets"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("graphicsAssets"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("runtimeAssets"))
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("sessionAssets"))
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
val buildLinuxDisplay by tasks.registering(Exec::class) {
    dependsOn(prepareDisplayDependencies)
    inputs.files(rootProject.file("native/display/linux.sh"), rootProject.file("native/display/probe.c"), rootProject.file("native/display/probe_vulkan.c"), rootProject.file("native/display/source.env"), rootProject.file("native/session/drm.c"), rootProject.file("native/session/robust.c"), rootProject.file("native/session/syscall.S"), file("src/debug/native/robust_probe.c"))
    inputs.property("ndkVersion", android.ndkVersion.orEmpty())
    val output = layout.buildDirectory.dir("linuxDisplay")
    outputs.files(output.map { it.file("probe/arm64-v8a/libwayland-probe.so") }, output.map { it.file("probe/arm64-v8a/libwayland-vulkan-probe.so") }, output.map { it.file("libwayland-client.so.0") }, output.map { it.file("libdeck-drm.so") }, output.map { it.file("libdeck-robust.so") }, output.map { it.file("probe/arm64-v8a/librobust-probe.so") })
    environment("NDK", File(android.sdkDirectory, "ndk/${android.ndkVersion}"))
    commandLine("bash", rootProject.file("native/display/linux.sh"), layout.buildDirectory.dir("display-deps").get().asFile, output.get().asFile)
}
val packageGraphicsLibraries by tasks.registering(Exec::class) {
    dependsOn(buildLinuxDisplay)
    inputs.files(rootProject.file("native/packages.sh"), rootProject.file("native/graphics/packages.sh"), rootProject.file("native/graphics/packages.tsv"))
    inputs.file(layout.buildDirectory.file("linuxDisplay/libwayland-client.so.0"))
    val output = layout.buildDirectory.dir("graphicsAssets")
    outputs.file(output.map { it.file("graphics-libraries.tar.xz") })
    commandLine("bash", rootProject.file("native/graphics/packages.sh"), layout.buildDirectory.dir("linuxDisplay").get().asFile, output.get().asFile)
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(packageGraphicsLibraries) }

val packageCoreutils by tasks.registering(Exec::class) {
    inputs.files(rootProject.file("native/packages.sh"), rootProject.file("native/runtime/coreutils.sh"), rootProject.file("native/runtime/packages.tsv"))
    val output = layout.buildDirectory.dir("runtimeAssets")
    outputs.file(output.map { it.file("coreutils.tar.xz") })
    commandLine("bash", rootProject.file("native/runtime/coreutils.sh"), output.get().asFile)
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(packageCoreutils) }

val packageSessionComponents by tasks.registering(Exec::class) {
    dependsOn(buildLinuxDisplay)
    inputs.files(rootProject.file("native/packages.sh"), rootProject.file("native/session/packages.sh"), rootProject.file("native/session/packages.tsv"), rootProject.file("native/session/sources.tsv"))
    val output = layout.buildDirectory.dir("sessionAssets")
    inputs.files(layout.buildDirectory.file("linuxDisplay/libdeck-drm.so"), layout.buildDirectory.file("linuxDisplay/libdeck-robust.so"))
    outputs.file(output.map { it.file("session-components.tar.xz") })
    commandLine("bash", rootProject.file("native/session/packages.sh"), output.get().asFile, layout.buildDirectory.dir("linuxDisplay").get().asFile)
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(packageSessionComponents) }

dependencies {
    implementation("org.apache.commons:commons-compress:1.28.0")
    implementation("org.tukaani:xz:1.12")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}
