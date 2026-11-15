"""Local executable configuration. Slack credentials never enter this process."""
import json
import re
import shutil
from pathlib import Path


def load(path):
    data = json.loads(path.read_text())
    workspace = Path(data['workspace']).expanduser().resolve()
    if not workspace.is_dir():
        raise ValueError('workspace must be an existing directory')
    projects = {}
    for alias, directory in data.get('projects', {}).items():
        if not re.fullmatch(r'[a-z][a-z0-9_-]*', alias):
            raise ValueError('project aliases must be lowercase words')
        projects[alias] = Path(directory).expanduser().resolve()
        if not projects[alias].is_dir():
            raise ValueError('project directories must exist')
    commands = {}
    for keyword, entry in data['commands'].items():
        if not re.fullmatch(r'\S{1,40}', keyword) or keyword.casefold() in commands:
            raise ValueError('keywords must be unique words ignoring case')
        if set(entry) != {'start', 'resume'}:
            raise ValueError('commands need start and resume arrays')
        commands[keyword.casefold()] = {}
        for mode in ('start', 'resume'):
            args = entry[mode]
            if not isinstance(args, list) or not args or any(not isinstance(a, str) or '\0' in a for a in args):
                raise ValueError('commands must be nonempty argument arrays')
            if ('{session_id}' in args) != (mode == 'resume'):
                raise ValueError('only resume must include a {session_id} argument')
            executable = shutil.which(args[0])
            if not executable:
                raise ValueError(f'executable not found for keyword {keyword}')
            commands[keyword.casefold()][mode] = [str(Path(executable).resolve()), *args[1:]]
    if not commands:
        raise ValueError('configure at least one keyword')
    timeout = data.get('timeout_seconds', 600)
    if not isinstance(timeout, (int, float)) or not 1 <= timeout <= 600:
        raise ValueError('timeout_seconds must be between 1 and 600')
    return {'workspace': workspace, 'projects': projects, 'commands': commands, 'timeout': timeout}


def route(text, config):
    if not isinstance(text, str) or not text or text[0].isspace() or len(text) > 12000:
        raise ValueError('invalid request')
    parts = text.split(maxsplit=1)
    if len(parts) != 2 or not parts[1].strip() or parts[0].casefold() not in config['commands']:
        raise ValueError('request must start with a configured keyword')
    keyword, request = parts[0].casefold(), parts[1].strip()
    selected = None
    first = len(request)
    for alias, directory in config['projects'].items():
        match = re.search(rf'(?<![\w-]){re.escape(alias)}(?![\w-])', request, re.IGNORECASE)
        if match and match.start() < first:
            first, selected = match.start(), directory
    return config['commands'][keyword], selected, request
