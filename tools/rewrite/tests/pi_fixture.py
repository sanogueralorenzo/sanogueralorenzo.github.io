#!/usr/bin/env python3
"""Disposable Pi protocol fixture: no provider calls or real credentials."""
import json
import os
import pathlib
import sys
import subprocess
import time

args = sys.argv[1:]
flags = ['--offline', '--no-session', '--no-tools', '--no-extensions', '--no-skills',
         '--no-prompt-templates', '--no-context-files', '--no-themes', '--no-approve']
if args[:2] == ['auth', 'check']:
    assert args[2] == '--provider' and args[3] in ['openai-codex', 'anthropic']
    assert args[4:] == ['--json', '--credentials']
    time.sleep(0.05)
    print(json.dumps({'status': 'ready', 'authType': 'oauth', 'credentials': 'disposable-fixture-token'}))
    sys.exit(0)
assert all(flag in args for flag in flags)
request = pathlib.Path(os.environ['PI_CODING_AGENT_DIR'])
assert request.resolve() == pathlib.Path.cwd().resolve()
expected = {'auth.json', 'settings.json'}
provider = args[args.index('--provider') + 1] if '--provider' in args else 'openai-codex'
if '--mode' in args and provider == 'openai-codex': expected.add('rewrite-priority.mjs')
assert set(p.name for p in request.iterdir()) == expected
assert request.stat().st_mode & 0o777 == 0o700
assert (request / 'auth.json').stat().st_mode & 0o777 == 0o600
assert os.environ['PI_OFFLINE'] == '1'
if '--help' in args:
    print(' '.join(flags + ['--system-prompt', '--mode', '--thinking', '--extension']))
    sys.exit(0)
snapshot = json.loads((request / 'auth.json').read_text())[provider]
assert snapshot['type'] == 'oauth' and snapshot['access'] == 'disposable-fixture-token' and snapshot['refresh'] == ''
assert args[args.index('--model') + 1] == ('gpt-5.6-luna' if provider == 'openai-codex' else 'claude-haiku-4-5-20251001')
assert args[args.index('--thinking') + 1] == 'off'
assert args[args.index('--mode') + 1] == 'rpc'
if provider == 'openai-codex':
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
else:
    assert '--extension' not in args

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
