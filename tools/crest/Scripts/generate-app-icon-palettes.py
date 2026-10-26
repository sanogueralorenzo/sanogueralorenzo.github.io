#!/usr/bin/env python3
"""Generate bundled palette icons from Crest's existing Icon Composer artwork."""
import colorsys
import json
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COLOR_SOURCE = ROOT / "CrestShared/Domain/BrowserSpace/Branding/BrowserSpaceBrandColor.swift"
PALETTE_SOURCE = ROOT / "CrestShared/Domain/BrowserSpace/Branding/BrowserSpaceHousePalette.swift"
ICON_ROOT = ROOT / "CrestShared/Resources/CrestIcon"
PREVIEWS = ROOT / "CrestShared/Resources/AppIconPreviews.xcassets"

def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")

def rgb(color):
    return tuple(int(color[i:i + 2], 16) / 255 for i in (1, 3, 5))

def hex_color(channels):
    return "#" + "".join(f"{round(channel * 255):02X}" for channel in channels)

def dark_flag_color(color, minimum_lightness):
    # Space fields are intentionally dark, but an app icon's small flag must
    # remain legible against the system dark background. Keep the palette's hue/saturation.
    hue, lightness, saturation = colorsys.rgb_to_hls(*rgb(color))
    return hex_color(colorsys.hls_to_rgb(hue, max(lightness, minimum_lightness), saturation))

def dark_rail_color(charge):
    # A pale, palette-tinted binding defines the left silhouette like the
    # original Crest icon, instead of merging into the tile background.
    return hex_color(channel + (1 - channel) * 0.68 for channel in rgb(charge))

def main():
    colors = {}
    for name, red, green, blue in re.findall(
        r"static let (\w+) = BrowserSpaceBrandColor\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\)",
        COLOR_SOURCE.read_text(),
    ):
        colors[name] = "#" + "".join(f"{round(float(v) * 255):02X}" for v in (red, green, blue))
    palettes = re.findall(r"case \.(\w+): \[\.(\w+), \.(\w+), \.(\w+)\]", PALETTE_SOURCE.read_text())
    PREVIEWS.mkdir(exist_ok=True)
    write_json(PREVIEWS / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    template = ICON_ROOT / "Crest.icon"
    for name, field, primary, charge in palettes:
        icon_name = "Crest" + name.title()
        destination = ICON_ROOT / (icon_name + ".icon")
        (destination / "Assets").mkdir(parents=True, exist_ok=True)
        (destination / "icon.json").write_text((template / "icon.json").read_text())
        for source in (template / "Assets").glob("*.svg"):
            content = source.read_text()
            if "Tinted" not in source.name and "Background" not in source.name:
                role = field if "Rail" in source.name or "Coral" in source.name else charge if "Butter" in source.name else primary
                color = colors[role]
                if "Dark" in source.name:
                    if "Rail" in source.name:
                        color = dark_rail_color(colors[charge])
                    else:
                        minimum = 0.34 if "Coral" in source.name else 0.64 if "Butter" in source.name else 0.50
                        color = dark_flag_color(color, minimum)
                content = re.sub(r'fill="#[0-9A-Fa-f]{6}"', f'fill="{color}"', content)
            (destination / "Assets" / source.name).write_text(content)
        # Flatten the exact standard layers for the selector; the OS renders the
        # selected .icon with its own light, dark, tinted, and clear treatment.
        layers = []
        for layer in ["Background", "Coral", "Sky", "Butter", "Rail"]:
            content = (destination / "Assets" / f"Crest{layer}.svg").read_text()
            inner = re.search(r"<svg[^>]*>(.*)</svg>", content, re.S).group(1)
            layers.append(inner.replace("crest-banner", f"crest-banner-{layer}"))
        preview = PREVIEWS / (icon_name + "Preview.imageset")
        preview.mkdir(exist_ok=True)
        (preview / "icon.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">' + "".join(layers) + "</svg>\n")
        write_json(preview / "Contents.json", {
            "images": [{"filename": "icon.svg", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True},
        })
    layers = []
    for layer in ["Background", "Coral", "Sky", "Butter", "Rail"]:
        content = (template / "Assets" / f"Crest{layer}.svg").read_text()
        inner = re.search(r"<svg[^>]*>(.*)</svg>", content, re.S).group(1)
        layers.append(inner.replace("crest-banner", f"crest-banner-{layer}"))
    preview = PREVIEWS / "CrestPreview.imageset"
    preview.mkdir(exist_ok=True)
    (preview / "icon.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">' + "".join(layers) + "</svg>\n")
    write_json(preview / "Contents.json", {
        "images": [{"filename": "icon.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True},
    })
    # Prepare complete Mac icons at 1x and 2x with Apple's renderer. Runtime callers
    # load these directly, avoiding implicit rendition selection or drawing caches.
    # Clear/Tinted still use the shared monochrome icon through Icon Services.
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    exporter = developer.parent / "Applications/Icon Composer.app/Contents/Executables/ictool"
    with tempfile.TemporaryDirectory(prefix="crest-icon-export-") as temporary:
        working = Path(temporary)
        padding_tool = working / "pad-mac-app-icon"
        subprocess.run(["xcrun", "swiftc", str(ROOT / "Scripts/pad-mac-app-icon.swift"),
                        "-o", str(padding_tool)], check=True)
        for source in ICON_ROOT.glob("Crest*.icon"):
            for appearance, rendition in [("Light", "Default"), ("Dark", "Dark")]:
                target = PREVIEWS / (source.stem + "Dock" + appearance + ".imageset")
                target.mkdir(exist_ok=True)
                images = []
                for scale in (1, 2):
                    filename = "icon.png" if scale == 1 else "icon@2x.png"
                    face = working / "face.png"
                    subprocess.run([str(exporter), str(source), "--export-image", "--output-file", str(face),
                                    "--platform", "macOS", "--rendition", rendition,
                                    "--width", "412", "--height", "412", "--scale", str(scale)],
                                   check=True, stdout=subprocess.DEVNULL)
                    subprocess.run([str(padding_tool), str(face), str(target / filename), str(512 * scale)], check=True)
                    images.append({"filename": filename, "idiom": "mac", "scale": f"{scale}x"})
                write_json(target / "Contents.json", {"images": images, "info": {"author": "xcode", "version": 1}})
    print(f"Generated {len(palettes)} palette icons and previews.")

if __name__ == "__main__":
    main()
