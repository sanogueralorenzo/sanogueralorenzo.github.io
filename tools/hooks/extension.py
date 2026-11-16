"""Build the unpacked extension in private application data, outside the checkout."""
import os
from pathlib import Path
import shutil
import tempfile


def prepare(checkout, data):
    target = data / 'extension'
    if target.resolve().is_relative_to(checkout.parents[1].resolve()):
        raise ValueError('Keep the generated extension outside the public repository')
    data.mkdir(parents=True, exist_ok=True, mode=0o700)
    data.chmod(0o700)
    # Only browser runtime files belong in the generated extension.
    with tempfile.TemporaryDirectory(dir=data) as folder:
        staging = Path(folder)
        source = checkout
        for name in ['manifest.json', 'background.mjs', 'bridge.mjs', 'popup', 'slack/extension', 'slack/hook.js', 'slack/icon.png']:
            origin, destination = source / name, staging / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            if origin.is_dir():
                shutil.copytree(origin, destination)
            else:
                shutil.copyfile(origin, destination)
        for entry in staging.rglob('*'):
            entry.chmod(0o700 if entry.is_dir() else 0o600)
        if target.exists():
            shutil.rmtree(target)
        os.replace(staging, target)
    return target
