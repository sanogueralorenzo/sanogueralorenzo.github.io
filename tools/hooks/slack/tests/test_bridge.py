import http.client
import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local.config import load, route
from local.runtime import Runtime
from local.server import Server
from local.service import specification


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.data = self.root / 'data'
        self.workspace = self.root / 'work'
        self.workspace.mkdir()
        self.project = self.root / 'project'
        self.project.mkdir()
        self.log = self.root / 'runs.jsonl'
        handler = self.root / 'handler.py'
        handler.write_text('''import json, os, sys, time
from pathlib import Path
prompt = sys.stdin.read()
with Path(sys.argv[1]).open('a') as f:
 f.write(json.dumps({'args': sys.argv[2:], 'cwd': os.getcwd(), 'prompt': prompt}) + '\\n')
if 'SLOW' in prompt: time.sleep(0.15)
if 'HANG' in prompt: time.sleep(30)
if 'AUTHFAIL' in prompt:
 print(json.dumps({'error': {'code': 'auth_required', 'provider': 'Claude', 'message': 'fixture-private-secret'}}))
 raise SystemExit(1)
if 'FAIL' in prompt: raise SystemExit(1)
print(json.dumps({'session_id': sys.argv[2] if len(sys.argv)>2 else 'synthetic-session', 'answer': 'synthetic answer'}))
''')
        self.config_path = self.root / 'config.json'
        self.config_path.write_text(json.dumps({'workspace': str(self.workspace), 'projects': {'demo': str(self.project)},
            'commands': {'hook': {'start': [sys.executable, str(handler), str(self.log)], 'resume': [sys.executable, str(handler), str(self.log), '{session_id}']}},
            'timeout_seconds': 2}))
        self.config = load(self.config_path)
        self.runtime = Runtime(self.config, self.root / 'state')

    def tearDown(self):
        self.runtime.close()
        self.temp.cleanup()

    def event(self, **extra):
        return {'team': 'ETEST', 'user': 'UTEST', 'channel': 'CTEST', 'ts': '2000000001.000001', 'thread_ts': '2000000001.000001',
                'text': 'hook ping', 'messages': [], **extra}

    def wait(self, job, status='ready'):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            result = self.runtime.status(job)
            if result['status'] == status:
                return result
            time.sleep(0.02)
        self.fail(f'job did not reach {status}: {result}')

    def runs(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_background_service_keeps_only_explicit_configuration_and_path(self):
        value = specification(Path(sys.executable), self.root / 'cli.py', self.data)
        self.assertTrue(value['RunAtLoad'])
        self.assertTrue(value['KeepAlive'])
        self.assertEqual(set(value['EnvironmentVariables']), {'PATH'})
        self.assertIn('serve', value['ProgramArguments'])
        self.assertNotIn('SLACK_USER_TOKEN', json.dumps(value))

    def test_keyword_and_project_routing_matches_reference(self):
        for text in ('hook', 'hook ', ' hook ping', 'other ping'):
            with self.assertRaises(ValueError): route(text, self.config)
        command, project, request = route('HOOK\tplease inspect demo now', self.config)
        self.assertEqual(project, self.project)
        self.assertEqual(request, 'please inspect demo now')
        self.assertEqual(command, self.config['commands']['hook'])

    def test_resume_delivery_claim_and_durable_deduplication(self):
        event = self.event(text='hook inspect demo')
        job = self.runtime.submit(event)['job']
        self.wait(job)
        self.assertTrue(self.runtime.claim(job)['claimed'])
        self.assertFalse(self.runtime.claim(job)['claimed'])
        self.runtime.delivered(job, '2000000002.000001')
        self.assertEqual(self.runtime.submit(event)['status'], 'delivered')
        next_job = self.runtime.submit(self.event(ts='2000000004.000001', messages=[
            {'ts': '2000000001.000001', 'user': 'UTEST', 'text': 'old request'},
            {'ts': '2000000002.000001', 'user': 'UTEST', 'text': 'own generated answer'},
            {'ts': '2000000003.000001', 'user': 'UOTHER', 'text': 'extra context'}]))['job']
        self.wait(next_job)
        runs = self.runs()
        self.assertEqual(runs[0]['args'], [])
        self.assertEqual(runs[1]['args'], ['synthetic-session'])
        self.assertEqual(runs[1]['cwd'], str(self.project))
        self.assertIn('extra context', runs[1]['prompt'])
        self.assertNotIn('old request', runs[1]['prompt'])
        self.assertNotIn('own generated answer', runs[1]['prompt'])
        self.runtime.close()
        self.runtime = Runtime(self.config, self.root / 'state')
        self.assertEqual(self.runtime.submit(event)['status'], 'delivered')
        self.assertEqual(len(self.runs()), 2)

    def test_sessions_are_isolated_across_channel_user_and_workspace(self):
        original = self.runtime.submit(self.event())['job']
        self.wait(original)
        for extra in ({'channel': 'DOTHER'}, {'user': 'UOTHER'}, {'team': 'EOTHER'}):
            self.wait(self.runtime.submit(self.event(**extra))['job'])
        changed = self.runtime.submit(self.event(ts='2000000005.000001', text='hook inspect demo'))['job']
        self.wait(changed)
        self.assertTrue(all(not r['args'] for r in self.runs()))
        self.assertEqual(self.runs()[-1]['cwd'], str(self.project))

    def test_each_thread_runs_in_order_other_threads_can_finish_first(self):
        first = self.runtime.submit(self.event(text='hook SLOW'))['job']
        second = self.runtime.submit(self.event(ts='2000000002.000001'))['job']
        other = self.runtime.submit(self.event(channel='GOTHER'))['job']
        self.wait(other)
        self.assertIn(self.runtime.status(first)['status'], ['running', 'queued'])
        self.wait(second)
        runs = self.runs()
        same = [r for r in runs if 'SLOW' in r['prompt'] or r['args']]
        self.assertIn('SLOW', same[0]['prompt'])
        self.assertEqual(same[1]['args'], ['synthetic-session'])

    def test_failed_or_cancelled_commands_never_produce_answers(self):
        with self.assertLogs(level='ERROR'):
            failed = self.runtime.submit(self.event(text='hook FAIL'))['job']
            self.wait(failed, 'failed')
        hung = self.runtime.submit(self.event(ts='2000000002.000001', text='hook HANG'))['job']
        self.wait(hung, 'running')
        self.runtime.cancel(hung)
        self.assertFalse(self.runtime.claim(hung)['claimed'])
        self.assertNotIn('answer', self.runtime.status(hung))

    def test_failed_requests_expose_safe_errors_and_claim_delivery_once_without_a_session(self):
        with self.assertLogs(level='ERROR') as logged:
            job = self.runtime.submit(self.event(text='hook AUTHFAIL'))['job']
            result = self.wait(job, 'failed')
        self.assertEqual(result['error']['code'], 'auth_required')
        self.assertIn('claude auth login', result['error']['message'])
        self.assertNotIn('fixture-private-secret', json.dumps(result) + str(logged.output))
        self.assertTrue(self.runtime.claim(job)['claimed'])
        self.assertFalse(self.runtime.claim(job)['claimed'])
        self.assertTrue(self.runtime.delivered(job, '2000000002.000001')['ok'])
        self.assertEqual(self.runtime.status(job)['status'], 'delivered')
        self.assertEqual(self.runtime.db.execute('SELECT count(*) FROM sessions').fetchone()[0], 0)

    def test_unknown_sends_and_interrupted_jobs_are_never_retried(self):
        event = self.event()
        job = self.runtime.submit(event)['job']
        self.wait(job)
        self.runtime.claim(job)
        self.runtime.close()
        self.runtime = Runtime(self.config, self.root / 'state')
        self.assertEqual(self.runtime.submit(event)['status'], 'sending')
        self.assertEqual(len(self.runs()), 1)

    def test_rejects_arbitrary_executables_credentials_and_invalid_events(self):
        for extra in ({'command': ['sh']}, {'token': 'synthetic-token'}, {'channel': 'https://example.com'}, {'text': 'unconfigured run'}):
            with self.assertRaises(ValueError): self.runtime.submit(self.event(**extra))

    def test_subprocess_input_is_not_interpolated_by_a_shell(self):
        marker = self.root / 'must-not-exist'
        job = self.runtime.submit(self.event(text=f'hook $(touch {marker}) ; echo nope'))['job']
        self.wait(job)
        self.assertFalse(marker.exists())
        self.assertIn('$(touch', self.runs()[0]['prompt'])

    def test_http_pairing_and_authenticated_bridge_with_no_slack_credentials(self):
        server = Server(('127.0.0.1', 0), self.runtime, self.data)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        origin = 'chrome-extension://' + 'a' * 32
        def call(method, path, body=None, headers=None):
            client = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
            merged = {'Content-Type': 'application/json', 'X-Browser-Hooks-Origin': origin, **(headers or {})}
            client.request(method, path, body=None if body is None else json.dumps(body), headers=merged)
            response = client.getresponse()
            value = json.loads(response.read())
            result = (response.status, value, dict(response.getheaders()))
            client.close()
            return result
        try:
            self.assertEqual(call('GET', '/config')[0], 403)
            self.assertEqual(call('GET', '/health')[1]['service'], 'browser-hooks-slack')
            self.assertEqual(call('GET', '/health', headers={'Host': 'evil.example'})[0], 403)
            self.assertEqual(call('POST', '/pair', {'code': server.pair_code}, {'Origin': 'https://app.slack.com'})[0], 403)
            bootstrap = json.loads(server.pair_file.read_text())
            self.assertEqual(bootstrap['code'], server.pair_code)
            self.assertGreater(bootstrap['expiresAt'], time.time() * 1000)
            self.assertEqual(server.pair_file.stat().st_mode & 0o777, 0o600)
            code = bootstrap['code']
            status, paired, _ = call('POST', '/pair', {'code': code})
            self.assertEqual(status, 200)
            self.assertFalse(server.pair_file.exists())
            self.assertEqual(call('POST', '/pair', {'code': code})[0], 403)
            headers = {'Authorization': 'Bearer ' + paired['token']}
            status, config, response_headers = call('GET', '/config', headers=headers)
            self.assertEqual(status, 200)
            self.assertEqual(config, {'keywords': ['hook']})
            self.assertNotIn('Access-Control-Allow-Origin', response_headers)
            self.assertEqual(call('GET', '/config', headers={**headers, 'X-Browser-Hooks-Origin': 'chrome-extension://' + 'b' * 32})[0], 403)
            self.assertEqual(call('GET', '/config', headers={**headers, 'Host': 'evil.example'})[0], 403)
            status, accepted, _ = call('POST', '/run', self.event(), headers)
            self.assertEqual(status, 200)
            self.wait(accepted['job'])
            self.assertEqual(call('GET', '/jobs/' + accepted['job'], headers=headers)[1]['answer'], 'synthetic answer')
            self.assertEqual(os.stat(self.data / 'hooks/slack/pairing.json').st_mode & 0o777, 0o600)
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_pairing_file_expires_without_requests_and_preserves_saved_credentials(self):
        credentials = self.data / 'hooks/slack/pairing.json'
        credentials.parent.mkdir(parents=True)
        saved = json.dumps({'origin': 'chrome-extension://' + 'a' * 32, 'token': 'synthetic-saved-token'})
        credentials.write_text(saved)
        server = Server(('127.0.0.1', 0), self.runtime, self.data)
        code = server.pair_code
        server.pair_deadline = time.monotonic() + 0.03
        thread = threading.Thread(target=lambda: server.serve_forever(poll_interval=0.01), daemon=True)
        thread.start()
        try:
            deadline = time.monotonic() + 2
            while server.pair_file.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            with server.pair_lock:
                self.assertFalse(server.pair_file.exists())
                self.assertIsNone(server.pair_code)
            self.assertEqual(credentials.read_text(), saved)
            client = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=3)
            try:
                client.request('POST', '/pair', json.dumps({'code': code}), {
                    'Content-Type': 'application/json', 'X-Browser-Hooks-Origin': 'chrome-extension://' + 'a' * 32})
                self.assertEqual(client.getresponse().status, 403)
            finally:
                client.close()
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_server_close_removes_unused_pairing_file(self):
        server = Server(('127.0.0.1', 0), self.runtime, self.data)
        self.assertTrue(server.pair_file.exists())
        server.server_close()
        self.assertFalse(server.pair_file.exists())
        self.assertIsNone(server.pair_code)
        server.server_close()  # Closing twice is harmless.


if __name__ == '__main__':
    unittest.main()
