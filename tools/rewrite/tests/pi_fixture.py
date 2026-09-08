#!/usr/bin/env python3
"""Disposable Pi protocol fixture: no provider calls or real credentials."""
import json
import os
import pathlib
import sys

args = sys.argv[1:]
flags = ['--offline', '--no-session', '--no-tools', '--no-extensions', '--no-skills',
         '--no-prompt-templates', '--no-context-files', '--no-themes', '--no-approve']
if args[:2] == ['auth', 'check']:
    assert args[2:] == ['--provider', 'openai-codex', '--json', '--credentials']
    print(json.dumps({'status': 'ready', 'authType': 'oauth', 'credentials': 'disposable-fixture-token'}))
    sys.exit(0)
assert all(flag in args for flag in flags)
request = pathlib.Path(os.environ['PI_CODING_AGENT_DIR'])
assert request.resolve() == pathlib.Path.cwd().resolve()
assert set(p.name for p in request.iterdir()) == {'auth.json', 'settings.json'}
assert request.stat().st_mode & 0o777 == 0o700
assert (request / 'auth.json').stat().st_mode & 0o777 == 0o600
assert os.environ['PI_OFFLINE'] == '1'
if '--help' in args:
    print(' '.join(flags + ['--system-prompt', '--mode', '--thinking']))
    sys.exit(0)
snapshot = json.loads((request / 'auth.json').read_text())['openai-codex']
assert snapshot['type'] == 'oauth' and snapshot['access'] == 'disposable-fixture-token' and snapshot['refresh'] == ''
if '--list-models' in args:
    print('provider model context max-out thinking images')
    print('openai-codex gpt-5.6-luna 272K 128K yes yes')
    print('ollama forbidden 32K 8K no no')
    sys.exit(0)
assert args[args.index('--provider') + 1] == 'openai-codex'
assert args[args.index('--model') + 1] == 'gpt-5.6-luna'
assert args[args.index('--thinking') + 1] == 'low'
assert args[args.index('--mode') + 1] == 'json'
assert 'single-purpose text rewriting harness' in args[args.index('--system-prompt') + 1]
payload = json.load(sys.stdin)
assert payload == {'editing_instruction': 'Correct spelling, grammar, and punctuation.', 'source_text': 'She go to the library yesterday.'}
assert not any(payload['source_text'] in arg for arg in args)
print(json.dumps({'type': 'message_end', 'message': {'role': 'assistant', 'stopReason': 'stop', 'content': [{'type': 'text', 'text': 'She went to the library yesterday.'}]}}))
print(json.dumps({'type': 'agent_end'}))
