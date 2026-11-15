"""XDG locations shared by setup and the command bridge."""
import os
from pathlib import Path


def root(variable, fallback):
    value = Path(os.environ.get(variable, ''))
    return value if value.is_absolute() else Path.home() / fallback


def data_root():
    return root('XDG_DATA_HOME', '.local/share') / 'browser-hooks'


def config_path():
    return root('XDG_CONFIG_HOME', '.config') / 'browser-hooks/slack.json'


def state_root():
    return root('XDG_STATE_HOME', '.local/state') / 'browser-hooks/slack'


def bin_root():
    return root('XDG_BIN_HOME', '.local/bin')
