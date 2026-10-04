package com.sanogueralorenzo.androidsteam.session

import android.system.Os
import android.system.OsConstants
import java.io.File
import java.nio.file.Files
import com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive

/** Give libdrm the identity of the KGSL device our pinned Turnip driver reports. */
internal object GpuDevice {
    fun bindings(directory: File): List<String> {
        RuntimeArchive.delete(directory)
        val device = "/dev/kgsl-3d0"
        val stat = Os.stat(device)
        require(OsConstants.S_ISCHR(stat.st_mode)) { "The Adreno GPU device is unavailable." }
        val major = ((stat.st_rdev ushr 8) and 0xfff) or ((stat.st_rdev ushr 32) and 0xfffff000L)
        val minor = (stat.st_rdev and 0xff) or ((stat.st_rdev ushr 12) and 0xffffff00L)
        val number = "$major:$minor"
        val node = "renderD$minor"
        val dri = File(directory, "dri")
        val sys = File(directory, "sys/$number")
        val gpu = File(sys, "device")
        val render = File(gpu, "drm/$node")
        val pci = File(directory, "pci")
        require(dri.mkdirs() && render.mkdirs() && pci.mkdirs()) { "Cannot prepare the Linux GPU device identity." }
        require(File(dri, node).createNewFile()) { "Cannot prepare the Linux GPU node." }
        // KGSL is a platform GPU. An empty PCI scan avoids libpci terminating
        // Chromium when Android hides /proc/bus/pci/devices.
        File(pci, "devices").writeText("")
        File(render, "dev").writeText("$number\n")
        File(gpu, "uevent").writeText("DRIVER=kgsl-3d0\nMODALIAS=platform:kgsl-3d0\n")
        Files.createSymbolicLink(File(gpu, "subsystem").toPath(), File("/sys/bus/platform").toPath())
        // Bind the parent: the kernel's device-number entry is itself a symlink,
        // which PRoot resolves before a binding on that entry can take effect.
        return listOf("${dri.path}:/dev/dri", "$device:/dev/dri/$node", "${File(directory, "sys").path}:/sys/dev/char",
            "${pci.path}:/proc/bus/pci")
    }
}
