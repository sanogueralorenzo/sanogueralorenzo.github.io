#!/usr/bin/env python3
"""Disposable Pi protocol fixture: no provider calls or real credentials."""
import json
import os
import pathlib
import sys
import subprocess

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
expected = {'auth.json', 'settings.json'}
if '--mode' in args and args[args.index('--mode') + 1] == 'rpc': expected.add('rewrite-priority.mjs')
assert set(p.name for p in request.iterdir()) == expected
assert request.stat().st_mode & 0o777 == 0o700
assert (request / 'auth.json').stat().st_mode & 0o777 == 0o600
assert os.environ['PI_OFFLINE'] == '1'
if '--help' in args:
    print(' '.join(flags + ['--system-prompt', '--mode', '--thinking', '--extension']))
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
assert args[args.index('--thinking') + 1] == 'off'
assert args[args.index('--mode') + 1] == 'rpc'
extension = pathlib.Path(args[args.index('--extension') + 1])
assert extension.parent == request
assert 'service_tier: "priority"' in extension.read_text()
assert 'effort: "none"' in extension.read_text()
subprocess.run(['node', '--input-type=module', '-e', """
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const {default: install} = await import(pathToFileURL(process.argv[1]));
let handler;
install({on(name, callback) { assert.equal(name, 'before_provider_request'); handler = callback; }});
const payload = {model: 'gpt-5.6-luna', input: ['fixture'], reasoning: {effort: 'low'}};
const result = handler({payload});
assert.equal(result.service_tier, 'priority');
assert.deepEqual(result.reasoning, {effort: 'none'});
assert.equal(result.model, payload.model);
assert.equal(result.input, payload.input);
assert.equal(payload.reasoning.effort, 'low');
""", str(extension)], check=True)

assert 'single-purpose text rewriting harness' in args[args.index('--system-prompt') + 1]
fresh = False
for line in sys.stdin.buffer:
    command = json.loads(line)
    if command['type'] == 'new_session':
        fresh = True
        print(json.dumps({'type': 'response', 'id': command['id'], 'command': 'new_session', 'success': True, 'data': {'cancelled': False}}), flush=True)
        continue
    if command['type'] == 'get_state':
        print(json.dumps({'type': 'response', 'id': command['id'], 'command': 'get_state', 'success': True, 'data': {'messageCount': 0 if fresh else 2, 'pendingMessageCount': 0, 'isStreaming': False}}), flush=True)
        continue
    assert command['type'] == 'prompt' and fresh, 'previous rewrite was not cleared'
    fresh = False
    payload = json.loads(command['message'])
    assert payload == {'editing_instruction': 'Correct spelling, grammar, and punctuation.', 'source_text': 'She go to the library yesterday.'}
    assert not any(payload['source_text'] in arg for arg in args)
    print(json.dumps({'type': 'response', 'id': command['id'], 'command': 'prompt', 'success': True}), flush=True)
    print(json.dumps({'type': 'message_end', 'message': {'role': 'assistant', 'stopReason': 'stop', 'content': [{'type': 'text', 'text': 'She went to the library yesterday.'}]}}), flush=True)
    print(json.dumps({'type': 'agent_end'}), flush=True)
