"""Keep upstream's shell; Android owns unavailable system controls and locking."""
import json
import os
from pathlib import Path

path = Path.home() / ".config/omarchy/shell.json"
config = json.loads(path.read_text())
unavailable = {
    "omarchy.idle", "omarchy.lock", "omarchy.polkit", "omarchy.battery",
    "omarchy.bluetooth", "omarchy.network", "omarchy.power", "omarchy.monitor", "omarchy.system-update",
}
config["disabledPlugins"] = sorted(set(config.get("disabledPlugins", [])) | unavailable)
config.setdefault("idle", {}).update(screensaver=0, lock=0)
for items in config["bar"]["layout"].values():
    items[:] = [item for item in items if item.get("id") not in unavailable]
temporary = path.with_suffix(".android-tmp")
temporary.write_text(json.dumps(config, indent=2) + "\n")
os.replace(temporary, path)

# Chromium cannot create its Linux namespace sandbox inside Android's app
# sandbox. Software rendering and a small renderer pool keep the host usable.
flags_path = Path.home() / ".config/chromium-flags.conf"
flags = flags_path.read_text().splitlines()
for flag in ("--no-sandbox", "--disable-gpu", "--renderer-process-limit=2", "--no-first-run", "--no-default-browser-check"):
    if flag not in flags:
        flags.append(flag)
flags_path.write_text("\n".join(flags) + "\n")
