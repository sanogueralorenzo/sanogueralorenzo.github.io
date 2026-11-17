"""Incremental history must agree with the native session selected for execution."""

import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import time
import unittest

from support import Backend, configuration, event


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='browser-hooks-history-')
        self.home = Path(self.temp.name).resolve()
        self.one, self.two = self.home/'one', self.home/'two'
        self.one.mkdir(); self.two.mkdir()
        script = self.home/'agent.py'
        script.write_text('''import json,os,sys,time,uuid
from pathlib import Path
root=Path(__file__).parent
provider=sys.argv[1]
prompt=sys.stdin.read()
session=sys.argv[2] if len(sys.argv)>2 else uuid.uuid4().hex
if provider=='codex': print(json.dumps({'type':'session','session_id':session}),flush=True)
with (root/'runs.jsonl').open('a') as log:
 log.write(json.dumps({'provider':provider,'mode':'resume' if len(sys.argv)>2 else 'start','session':session,'cwd':os.getcwd(),'prompt':prompt})+'\\n')
if prompt.endswith('hold'):
 while not (root/'release').exists(): time.sleep(.01)
if prompt.endswith('fail'):
 print(json.dumps({'error':{'code':'command_failed'}}));raise SystemExit(1)
print(json.dumps({'session_id':session,'answer':'answer'}))
''')
        config = configuration(self.home)
        for keyword, provider in [('hook','codex'),('alias','codex'),('claude','claude')]:
            args = [sys.executable,str(script),provider]
            config['commands'][keyword] = {'start':args,'resume':args+['{session_id}']}
        config['projects'] = {'one':str(self.one),'two':str(self.two)}
        self.backend = Backend(self.home, config)
        self.db = sqlite3.connect(self.home/'hooks/slack/sessions.sqlite3')

    def tearDown(self):
        (self.home/'release').touch()
        self.backend.stop()
        self.db.close()
        self.temp.cleanup()

    def submit(self, text='hook next', ts='2000000002.000001', **extra):
        return self.backend.request('POST','/slack/run',event(text=text,ts=ts,**extra))['job']

    def history(self, text='hook next', ts='2000000002.000001', **extra):
        return self.backend.request('POST','/slack/history',event(text=text,ts=ts,**extra))['after']

    def seed(self):
        self.backend.wait(self.submit('hook one first','2000000001.000001'))

    def runs(self):
        return [json.loads(line) for line in (self.home/'runs.jsonl').read_text().splitlines()]

    def test_checkpoint_requires_same_command_and_project_and_only_advances_on_success(self):
        self.assertIsNone(self.history())
        self.seed()
        self.assertEqual(self.history(), '2000000001.000001')
        self.assertEqual(self.history('alias next'), '2000000001.000001')
        self.assertIsNone(self.history('claude next'))
        self.assertIsNone(self.history('hook two next'))
        self.assertIsNone(self.history(channel='COTHER'))
        self.assertIsNone(self.history(thread_ts='2000000002.000001'))
        self.backend.wait(self.submit('hook fail'), 'failed')
        self.assertEqual(self.history(ts='2000000003.000001'), '2000000001.000001')
        for text in ['hook two next','claude next']:
            with self.subTest(text=text):
                self.assertIsNone(self.history(text,'2000000003.000001'))

    def test_project_and_provider_switches_start_with_full_thread_context(self):
        self.seed()
        messages = [{'ts':'2000000000.000001','user':'UOTHER','text':'Earlier discussion'}]
        for number, text in [(2,'hook two change'),(3,'claude change'),(4,'hook one change')]:
            with self.subTest(text=text):
                after = self.history(text,f'200000000{number}.000001')
                self.assertIsNone(after)
                self.backend.wait(self.submit(text,f'200000000{number}.000001',messages=messages,history_after=after))
                run = self.runs()[-1]
                self.assertEqual(run['mode'], 'start')
                self.assertIn('Earlier discussion', run['prompt'])
        self.assertEqual(self.history(ts='2000000005.000001'), '2000000004.000001')
        self.assertEqual(self.runs()[-1]['cwd'], str(self.one))

    def queued_switch(self, switch):
        self.seed()
        held = self.submit('hook hold')
        self.backend.wait(held,'running')
        end = time.monotonic()+5
        while len(self.runs()) < 2:
            self.assertLess(time.monotonic(),end)
            time.sleep(.01)
        self.assertEqual(self.history(ts='2000000004.000001'), '2000000001.000001')
        changed = self.submit(switch,'2000000003.000001')
        self.assertEqual(self.backend.request('GET','/slack/jobs/'+changed)['status'], 'queued')
        self.assertIsNone(self.history('hook one next','2000000004.000001'))
        messages = [{'ts':'2000000000.000001','user':'UOTHER','text':'Original discussion'}]
        followup = self.submit('hook one next','2000000004.000001',messages=messages)
        (self.home/'release').touch()
        for job in [held,changed,followup]: self.backend.wait(job)
        self.assertEqual(self.runs()[-1]['mode'], 'start')
        self.assertIn('Original discussion', self.runs()[-1]['prompt'])

    def test_queued_provider_switch_cannot_reuse_an_earlier_checkpoint(self):
        self.queued_switch('claude change')

    def test_queued_project_switch_cannot_reuse_an_earlier_checkpoint(self):
        self.queued_switch('hook two change')

    def test_route_change_during_fetch_rejects_partial_context_before_starting_an_agent(self):
        self.seed()
        stale = self.history('hook next','2000000003.000001')
        self.backend.wait(self.submit('hook two change'))
        count = len(self.runs())
        failed = self.submit('hook one next','2000000003.000001',history_after=stale)
        self.assertEqual(self.backend.wait(failed,'failed')['error']['code'], 'context_changed')
        self.assertEqual(len(self.runs()), count)
        self.assertIsNone(self.history('hook one retry','2000000004.000001'))

    def test_out_of_order_request_does_not_move_the_completed_checkpoint_backwards(self):
        self.seed()
        self.backend.wait(self.submit('hook newer','2000000003.000001'))
        self.backend.wait(self.submit('hook older','2000000002.000001',history_after='2000000003.000001'))
        self.assertEqual(self.history(ts='2000000004.000001'), '2000000003.000001')
