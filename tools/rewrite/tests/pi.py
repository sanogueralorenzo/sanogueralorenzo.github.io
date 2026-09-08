#!/usr/bin/env python3
"""Offline Pi stand-in. Records only synthetic test data in its own temporary directory."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).parent
args = sys.argv[1:]
flags = ['--offline', '--no-session', '--no-tools', '--no-extensions', '--no-skills',
         '--no-prompt-templates', '--no-context-files', '--no-themes', '--no-approve']

def record(event, **fields):
    with (root / 'events.jsonl').open('a') as out:
        out.write(json.dumps(dict(event=event, pid=os.getpid(), **fields)) + '\n')

def emit(value):
    data = (json.dumps(value) + '\n').encode()
    sys.stdout.buffer.write(data[:7]); sys.stdout.buffer.flush()
    sys.stdout.buffer.write(data[7:]); sys.stdout.buffer.flush()

if args[:2] == ['auth', 'check']:
    assert args[2] == '--provider' and args[3] in ['openai-codex', 'anthropic']
    assert args[4:] == ['--json', '--credentials']
    emit(dict(status='ready', authType='oauth', credentials='test-access-token'))
    sys.exit(0)
if '--help' in args:
    print(' '.join(flags + ['--system-prompt', '--mode', '--thinking', '--extension']))
    sys.exit(0)

assert all(flag in args for flag in flags)
provider = args[args.index('--provider') + 1]
assert args[args.index('--model') + 1] == {'openai-codex': 'gpt-5.6-luna', 'anthropic': 'claude-haiku-4-5-20251001'}[provider]
assert args[args.index('--thinking') + 1] == 'off'
assert args[args.index('--mode') + 1] == 'rpc'
assert args[args.index('--system-prompt') + 1]
directory = Path(os.environ['PI_CODING_AGENT_DIR'])
assert directory.resolve() == Path.cwd().resolve()
assert directory.stat().st_mode & 0o777 == 0o700
assert (directory / 'auth.json').stat().st_mode & 0o777 == 0o600
credential = json.loads((directory / 'auth.json').read_text())[provider]
assert credential['access'] == 'test-access-token' and credential['refresh'] == ''
assert json.loads((directory / 'settings.json').read_text()) == {'compaction': {'enabled': False}, 'retry': {'enabled': False}}
expected = {'auth.json', 'settings.json'}
if provider == 'openai-codex':
    extension = Path(args[args.index('--extension') + 1])
    assert extension.parent == directory
    expected.add(extension.name)
    subprocess.run(['node', '--input-type=module', '-e', '''
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
const {default: install} = await import(pathToFileURL(process.argv[1]));
let hook;
install({on(event, handler) { assert.equal(event, 'before_provider_request'); hook = handler; }});
const result = hook({payload: {input: ['test'], reasoning: {effort: 'high'}}});
assert.deepEqual(result, {input: ['test'], reasoning: {effort: 'none'}, service_tier: 'priority'});
''', str(extension)], check=True)
else:
    assert '--extension' not in args
assert {p.name for p in directory.iterdir()} == expected
record('started', provider=provider, directory=str(directory))
fresh = False
for line in sys.stdin:
    command = json.loads(line)
    mode = (root / 'mode').read_text()
    reply = dict(type='response', id=command['id'], command=command['type'], success=True)
    if command['type'] == 'new_session':
        fresh = True
        reply['data'] = dict(cancelled=False)
    elif command['type'] == 'get_state':
        reply['data'] = dict(messageCount=0 if fresh and mode != 'dirty' else 1, pendingMessageCount=0, isStreaming=False)
        record('state', clean=reply['data']['messageCount'] == 0)
    else:
        assert command['type'] == 'prompt' and fresh
        payload = json.loads(command['message'])
        assert set(payload) == {'source_text'}
        assert payload['source_text'] not in args
        record('prompt', mode=mode, source=payload['source_text'])
        fresh = False
        if mode == 'hold':
            time.sleep(60)
        elif mode == 'invalid':
            print('not JSON', flush=True); continue
        elif mode == 'tool':
            emit(dict(type='tool_execution_start')); continue
        emit(dict(type='message_end', message=dict(role='assistant', stopReason='length' if mode == 'partial' else 'stop',
             content=[dict(type='thinking', thinking='private'), dict(type='text', text='Edited: ' + payload['source_text'])])))
        emit(dict(type='agent_end'))
    # Complete before acknowledgment, and include an unrelated response ID.
    emit(dict(reply, id='unrelated'))
    emit(reply)
