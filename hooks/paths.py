"""One private application directory for Browser Hooks."""
import os
from pathlib import Path


def app_home():
    return Path(os.environ.get('BROWSER_HOOKS_HOME') or Path.home() / '.local/share/browser-hooks').expanduser()
