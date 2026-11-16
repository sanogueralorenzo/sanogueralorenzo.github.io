"""The idle service must still answer requests and exit cleanly on SIGTERM."""
import http.client
import json
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import unittest


class CommandTests(unittest.TestCase):
    def test_idle_service_answers_requests_and_stops_on_sigterm(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            folder = home / 'hooks/slack'
            folder.mkdir(parents=True)
            command = [sys.executable, '-c', 'pass']
            (folder / 'config.json').write_text(json.dumps({'workspace': directory,
                'commands': {'chat': {'start': command, 'resume': command + ['{session_id}']}}}))
            # Use a temporary port so this test never touches an installed bridge.
            script = '''from pathlib import Path
import sys
from local import commands
from local.server import Server
commands.Server = lambda address, runtime, home: Server(('127.0.0.1', 0), runtime, home)
commands.serve(Path(sys.argv[1]))
'''
            process = subprocess.Popen([sys.executable, '-c', script, directory],
                cwd=Path(__file__).resolve().parents[1], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                self.assertTrue(select.select([process.stdout], [], [], 5)[0], 'Bridge did not start')
                address = process.stdout.readline().strip().rsplit(' ', 1)[-1]
                self.assertTrue(address.startswith('127.0.0.1:'), address)
                client = http.client.HTTPConnection(address, timeout=3)
                try:
                    client.request('GET', '/health')
                    response = client.getresponse()
                    self.assertEqual(response.status, 200)
                    self.assertEqual(json.loads(response.read())['service'], 'browser-hooks-slack')
                finally:
                    client.close()
                self.assertTrue((home / 'extension/bridge-pairing.json').exists())
                process.send_signal(signal.SIGTERM)
                _, error = process.communicate(timeout=3)
                self.assertEqual(process.returncode, 0, error)
                self.assertFalse((home / 'extension/bridge-pairing.json').exists())
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()


if __name__ == '__main__':
    unittest.main()
