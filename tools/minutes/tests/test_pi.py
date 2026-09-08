"""Exercise RPC isolation and failure paths with a real subprocess, without provider access."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).parents[1] / 'Resources'))
from pi_processor import PiProcessor, stop_active
from notes import summarize

FAKE = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
if '--help' in sys.argv:
    print(' '.join(sys.argv) + ' --mode --system-prompt --thinking --extension')
    sys.exit()
if sys.argv[1] == 'auth':
    print(json.dumps(dict(status='ready', authType='oauth', credentials='fixture-access')))
    sys.exit()
root = Path(os.environ['PI_CODING_AGENT_DIR'])
auth = json.loads((root/'auth.json').read_text())
provider = sys.argv[sys.argv.index('--provider')+1]
model = sys.argv[sys.argv.index('--model')+1]
assert auth[provider]['refresh'] == ''
assert (root/'auth.json').stat().st_mode & 0o777 == 0o600
assert not os.environ.get('ANTHROPIC_API_KEY')
assert all(flag in sys.argv for flag in ['--no-tools','--no-extensions','--no-context-files','--no-session','--no-skills'])
assert sys.argv[sys.argv.index('--thinking')+1] == 'off'
if provider == 'openai-codex':
    assert 'effort:"none"' in Path(sys.argv[sys.argv.index('--extension')+1]).read_text()
count = 0
for line in sys.stdin:
    command = json.loads(line)
    kind = command['type']
    data = {}
    if kind == 'new_session': count = 0
    if kind == 'get_state': data = dict(messageCount=count,pendingMessageCount=0,isStreaming=False,model=dict(id=model,provider=provider,contextWindow=200000,maxTokens=64000))
    if kind == 'prompt':
        assert count == 0
        count += 2
        source = command['message']
        if source == 'exit': sys.exit(1)
        with (Path(sys.argv[0]).parent / 'requests').open('a') as log:
            log.write(str(os.getpid()) + chr(10))
        if len(source) > 100:
            source = json.dumps(dict(title='Fixture',recap='Summary.',decisions=[],actions=[],questions=[]))
        reason = 'length' if source == 'partial' else 'stop'
        content = [{'type':'toolCall'}] if source == 'tool' else [{'type':'text','text':source}]
        print(json.dumps(dict(type='message_end',message=dict(role='assistant',stopReason=reason,content=content))),flush=True)
        print(json.dumps(dict(type='agent_end')),flush=True)
    print(json.dumps(dict(type='response',id=command['id'],success=True,data=data)),flush=True)
'''

class PiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        executable = Path(self.tmp.name) / 'pi'
        executable.write_text(FAKE)
        executable.chmod(0o700)
        self.mock = patch('pi_processor.shutil.which', return_value=str(executable))
        self.mock.start()
        self.addCleanup(self.mock.stop)

    def test_both_providers_are_isolated_and_sessions_are_fresh(self):
        for provider in ('openai', 'anthropic'):
            with PiProcessor(provider, 'fixture system rules') as processor:
                root = Path(processor.directory.name)
                process = processor.process
                self.assertEqual(processor.generate('first transcript'), 'first transcript')
                self.assertEqual(processor.generate('second transcript'), 'second transcript')
            self.assertIsNotNone(process.poll())
            self.assertFalse(root.exists())

    def test_partial_tools_and_crashes_never_return_a_note(self):
        for source in ('partial', 'tool', 'exit'):
            with self.assertRaises(RuntimeError):
                with PiProcessor('anthropic', 'fixture rules') as processor:
                    process = processor.process
                    processor.generate(source)
            self.assertIsNotNone(process.poll())

    def test_job_reuses_one_process_and_then_cleans_up(self):
        with tempfile.TemporaryDirectory() as folder:
            result = summarize('a' * 300000, {'provider':'openai'}, Path(folder))
            self.assertEqual(result['title'], 'Fixture')
            requests = (Path(self.tmp.name) / 'requests').read_text().splitlines()
            self.assertGreater(len(requests), 1)
            self.assertEqual(len(set(requests)), 1)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(requests[0]), 0)

    def test_timeout_cleans_up_process_and_credentials(self):
        with self.assertRaises(TimeoutError):
            with PiProcessor('anthropic', 'rules') as processor:
                process = processor.process
                root = Path(processor.directory.name)
                with patch('pi_processor.select.select', return_value=([], [], [])):
                    processor.generate('deadline')
        self.assertIsNotNone(process.poll())
        self.assertFalse(root.exists())

    def test_cancellation_removes_credentials(self):
        with PiProcessor('anthropic', 'rules') as processor:
            root = Path(processor.directory.name)
            stop_active()
            processor.process.wait(timeout=2)
            self.assertFalse(root.exists())

    def test_long_jobs_refresh_credentials_between_requests(self):
        with PiProcessor('openai', 'rules') as processor:
            first = processor.process
            processor.started -= 181
            self.assertEqual(processor.generate('next'), 'next')
            self.assertIsNotNone(first.poll())
            self.assertNotEqual(first.pid, processor.process.pid)
