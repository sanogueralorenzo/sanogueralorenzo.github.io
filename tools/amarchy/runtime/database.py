"""Record the packages actually bundled so upstream tools can query their ownership."""
import io
import tarfile


def add_bytes(archive, path, data, mode=0o644):
    entry = tarfile.TarInfo(path)
    entry.size, entry.mode = len(data), mode
    archive.addfile(entry, io.BytesIO(data))
    return len(data)


def record(archive, package, files, description, build_date=0):
    values = {
        "NAME": [package["name"]], "VERSION": [package["version"]], "DESC": [description],
        "URL": [package["upstream"]], "ARCH": [package["architecture"]], "BUILDDATE": [str(build_date)],
        "INSTALLDATE": ["0"], "SIZE": [str(package["installedBytes"])], "REASON": ["0"],
        "LICENSE": package["licenses"], "VALIDATION": ["sha256"],
        "DEPENDS": package["depends"], "PROVIDES": package["provides"],
        "CONFLICTS": package["conflicts"], "REPLACES": package["replaces"],
    }
    prefix = "var/lib/pacman/local/" + package["name"] + "-" + package["version"] + "/"
    desc = "".join("%" + key + "%\n" + "\n".join(items) + "\n\n" for key, items in values.items() if items)
    file_list = "%FILES%\n" + "\n".join(sorted(files)) + "\n\n"
    return add_bytes(archive, prefix + "desc", desc.encode()) + add_bytes(archive, prefix + "files", file_list.encode())


def record_package(output, package, source):
    info = {}
    for line in source.extractfile(".PKGINFO").read().decode().splitlines():
        if " = " in line:
            key, value = line.split(" = ", 1)
            info.setdefault(key, []).append(value)
    if info["pkgname"] != [package["name"]] or info["pkgver"] != [package["version"]] or info["arch"] != [package["architecture"]]:
        raise ValueError(f"Package identity/architecture mismatch: {package['name']}")
    files = {item.name.removeprefix("./").rstrip("/") + ("/" if item.isdir() else "") for item in source.getmembers()
             if item.name.removeprefix("./") and not item.name.removeprefix("./").startswith(".")}
    return record(output, package, files, info["pkgdesc"][0], int(info.get("builddate", ["0"])[0]))
