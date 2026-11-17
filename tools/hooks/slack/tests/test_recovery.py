"""Recovery of accepted requests and replies across process boundaries."""

import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest

from support import Backend, bridge_binary, configuration, event


class RecoveryTests(unittest.TestCase):
    def test_restart_restores_queue_and_outbox_without_replaying_running_work(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            project = home / 'original project'
            project.mkdir()
            script = home / 'agent.py'
            script.write_text('''import json,os,sys,time
from pathlib import Path
root=Path(__file__).parent
prompt=sys.stdin.read()
session=sys.argv[1] if len(sys.argv)>1 else 'original-session'
print(json.dumps({'type':'session','session_id':session}),flush=True)
with (root/'runs.jsonl').open('a') as log:
 log.write(json.dumps({'cwd':os.getcwd(),'session':session,'prompt':prompt})+'\\n')
if prompt.endswith('hold'):
 while True: time.sleep(.1)
print(json.dumps({'session_id':session,'answer':'completed'}))
''')
            args = [sys.executable, str(script)]
            config = configuration(home)
            config['commands']['hook'] = {'start':args, 'resume':args+['{session_id}']}
            config['projects'] = {'demo':str(project)}
            backend = Backend(home, config)
            try:
                ready = backend.request('POST', '/slack/run', event(text='hook demo ready'))['job']
                backend.wait(ready)
                first = event(channel='CSECOND', ts='2000000002.000001', thread_ts='2000000002.000001', text='hook demo hold')
                running = backend.request('POST', '/slack/run', first)['job']
                backend.wait(running, 'running')
                # The early session checkpoint is committed before submitting the queued follow-ups.
                with sqlite3.connect(home/'hooks/slack/sessions.sqlite3') as db:
                    end = time.monotonic()+5
                    while db.execute('SELECT session FROM jobs WHERE id=?',(running,)).fetchone()[0] is None:
                        self.assertLess(time.monotonic(), end)
                        time.sleep(.01)
                queued = []
                for number, text in [(3,'second'), (4,'third')]:
                    queued.append(backend.request('POST', '/slack/run', event(channel='CSECOND', ts=f'200000000{number}.000001', thread_ts=first['thread_ts'], text='hook '+text))['job'])
                self.assertEqual(backend.request('GET', '/slack/jobs/'+queued[0])['status'], 'queued')
                backend.stop()
                # Recovery must use the accepted command/project, even if configuration changes.
                replacement = configuration(home, 'raise SystemExit("must not run")')
                replacement['commands']['changed'] = replacement['commands'].pop('hook')
                (home/'hooks/slack/config.json').write_text(json.dumps(replacement))
                backend.start()
                self.assertEqual(backend.request('GET', '/slack/jobs/'+running)['error']['code'], 'interrupted')
                self.assertEqual(backend.request('GET', '/slack/jobs/'+ready)['answer'], 'completed')
                for job in queued:
                    self.assertEqual(backend.wait(job)['answer'], 'completed')
                runs = [json.loads(line) for line in (home/'runs.jsonl').read_text().splitlines()]
                self.assertEqual(len(runs), 4)
                self.assertTrue(all(run['cwd']==str(project) for run in runs))
                self.assertTrue(all(run['session']=='original-session' for run in runs))
                self.assertTrue(runs[-2]['prompt'].endswith('second'))
                self.assertTrue(runs[-1]['prompt'].endswith('third'))
                # A repeated event returns its original receipt before checking current routing.
                self.assertEqual(backend.request('POST', '/slack/run', first)['job'], running)
                scope = {'team':'ETEST','user':'UTEST'}
                recovered = backend.request('POST', '/slack/recover', scope)['jobs']
                self.assertEqual([item['job'] for item in recovered], [ready,running,*queued])
                self.assertEqual(set(recovered[0]['event']), {'channel','ts','thread_ts'})
                for other in [dict(scope,team='EOTHER'),dict(scope,user='UOTHER')]:
                    self.assertEqual(backend.request('POST', '/slack/recover', other), {'jobs':[]})
                with self.assertRaises(ValueError):
                    backend.request('POST', '/slack/recover', dict(scope,token='synthetic-secret'))
            finally:
                backend.stop()

    def test_second_bridge_cannot_recover_work_owned_by_a_running_bridge(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            backend = Backend(home, configuration(home, 'import time;time.sleep(30)'))
            try:
                job = backend.request('POST', '/slack/run', event())['job']
                backend.wait(job, 'running')
                second = subprocess.run([str(bridge_binary()),'serve','--home',str(home),'--port','0'], capture_output=True, text=True, timeout=5)
                self.assertNotEqual(second.returncode, 0)
                self.assertIn('already running', second.stderr)
                self.assertEqual(backend.request('GET', '/slack/jobs/'+job)['status'], 'running')
            finally:
                backend.stop()

    def test_reply_receipts_keep_their_session_and_unknown_sends_are_not_replayed(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            one, two = home/'one', home/'two'
            one.mkdir(); two.mkdir()
            config = configuration(home, 'import json,os;from pathlib import Path;print(json.dumps({"session_id":Path.cwd().name,"answer":"completed"}))')
            config['projects'] = {'one':str(one),'two':str(two)}
            backend = Backend(home, config)
            db = sqlite3.connect(home/'hooks/slack/sessions.sqlite3')
            try:
                first = backend.request('POST', '/slack/run', event(text='hook one'))['job']
                backend.wait(first)
                second = backend.request('POST', '/slack/run', event(ts='2000000002.000001',text='hook two'))['job']
                backend.wait(second)
                self.assertTrue(backend.request('POST', '/slack/claim', {'job':first})['claimed'])
                # Kill only after execution has finished; the ambiguous send must remain withheld.
                backend.process.kill()
                backend.stop()
                backend.start()
                self.assertEqual(backend.request('GET', '/slack/jobs/'+first)['status'], 'sending')
                self.assertFalse(backend.request('POST', '/slack/claim', {'job':first})['claimed'])
                scope = {'team':'ETEST','user':'UTEST'}
                self.assertEqual([item['job'] for item in backend.request('POST','/slack/recover',scope)['jobs']], [second])
                self.assertEqual(db.execute('SELECT answer FROM jobs WHERE id=?',(first,)).fetchone()[0], 'completed')
                backend.request('POST', '/slack/delivered', {'job':first,'ts':'2000000003.000001'})
                self.assertEqual(db.execute('SELECT session FROM replies').fetchone()[0], 'one')
                self.assertEqual(db.execute('SELECT answer,request FROM jobs WHERE id=?',(first,)).fetchone(), (None,None))
                self.assertTrue(backend.request('POST', '/slack/claim', {'job':second})['claimed'])
                backend.request('POST', '/slack/delivered', {'job':second,'ts':'2000000004.000001'})
                self.assertEqual(backend.request('POST','/slack/recover',scope)['jobs'], [])
            finally:
                backend.stop()
                db.close()
