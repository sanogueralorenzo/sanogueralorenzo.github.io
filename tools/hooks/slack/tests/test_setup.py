import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from installation import install as install_hooks, launcher
from paths import app_home
from slack.local.config import load
from slack.local.setup import configure
from slack.local.service import install_linux, linux_unit


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / 'app'
        self.folder = self.home / 'hooks/slack'
        self.path = self.folder / 'config.json'
        self.checkout = Path(__file__).resolve().parents[2]

    def tearDown(self):
        self.temp.cleanup()

    def configure(self):
        with patch('slack.local.setup.shutil.which', return_value=sys.executable):
            return configure(self.path, self.checkout / 'slack', self.root)

    def test_first_install_discovers_both_clis_and_defaults_to_chat_and_claude(self):
        config = self.configure()
        self.assertEqual(set(config['commands']), {'chat', 'claude'})
        self.assertTrue(config['commands']['chat']['start'][1].endswith('/slack/agents/codex.py'))
        self.assertEqual(config['commands']['claude']['resume'][-1], '{session_id}')
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_rerun_preserves_custom_keywords_projects_pairing_and_sessions(self):
        self.configure()
        config = json.loads(self.path.read_text())
        config['commands']['custom'] = config['commands'].pop('chat')
        config['projects'] = {'demo': str(self.root)}
        self.path.write_text(json.dumps(config))
        before = self.path.read_bytes()
        sessions = self.folder / 'sessions.sqlite3'
        sessions.write_bytes(b'existing sessions')
        saved_key = self.folder / 'pairing.json'
        saved_key.write_text('synthetic-current-key')
        with patch('installation.launcher', return_value=self.root / 'browser-hooks'), patch('slack.local.setup.install') as install, patch('slack.local.setup.health', return_value={'paired': True}), contextlib.redirect_stdout(io.StringIO()):
            install_hooks(self.home, self.checkout, self.root)
        install.assert_called_once_with(self.checkout / 'cli.py', self.home)
        self.assertEqual(saved_key.read_text(), 'synthetic-current-key')
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(sessions.read_bytes(), b'existing sessions')

    def test_first_install_builds_private_extension_without_printing_a_secret(self):
        with patch('slack.local.setup.shutil.which', return_value=sys.executable), patch('installation.launcher', return_value=self.root / 'browser-hooks'), patch('slack.local.setup.install'), patch('slack.local.setup.health', return_value={'paired': False}), contextlib.redirect_stdout(io.StringIO()) as output:
            install_hooks(self.home, self.checkout, self.root)
        self.assertIn('Load unpacked', output.getvalue())
        self.assertIn('no code to copy', output.getvalue())
        extension = self.home / 'extension'
        self.assertIn(str(extension), output.getvalue())
        self.assertFalse(extension.is_relative_to(self.checkout.parents[1]))
        self.assertTrue((extension / 'manifest.json').is_file())
        self.assertTrue((extension / 'slack/extension/background.mjs').is_file())
        self.assertFalse((extension / 'slack/local').exists())
        self.assertFalse((extension / 'slack/tests').exists())
        self.assertEqual(extension.stat().st_mode & 0o777, 0o700)
        self.assertEqual((extension / 'manifest.json').stat().st_mode & 0o777, 0o600)

    def test_private_home_inside_the_repository_is_rejected_before_writing(self):
        result = subprocess.run([sys.executable, str(self.checkout / 'cli.py'), 'install', '--home', str(self.checkout / 'private-state')], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('outside the public repository', result.stderr)
        self.assertFalse((self.checkout / 'private-state').exists())

    def test_launcher_executes_from_any_directory_with_one_private_home(self):
        with patch('installation.Path.home', return_value=self.root / 'home with spaces'):
            path = launcher(self.home, self.checkout)
        result = subprocess.run([str(path), 'slack', '--help'], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('status,serve', result.stdout)
        self.assertEqual(path.name, 'browser-hooks')
        self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        self.assertIn(str(self.home), path.read_text())
        self.assertNotIn('--config', path.read_text())

    def test_one_home_override_replaces_separate_config_state_and_data_overrides(self):
        with patch.dict('os.environ', {'BROWSER_HOOKS_HOME': str(self.home)}):
            self.assertEqual(app_home(), self.home)
        with patch.dict('os.environ', {'BROWSER_HOOKS_HOME': '', 'XDG_CONFIG_HOME': '/unused', 'XDG_DATA_HOME': '/unused', 'XDG_STATE_HOME': '/unused'}), patch('paths.Path.home', return_value=self.root):
            self.assertEqual(app_home(), self.root / '.local/share/browser-hooks')

    def test_missing_clis_and_bad_config_have_actionable_errors_without_overwriting(self):
        with patch('slack.local.setup.shutil.which', return_value=None), self.assertRaisesRegex(ValueError, 'Install and sign in'):
            configure(self.path, self.checkout / 'slack', self.root)
        self.assertFalse(self.path.exists())
        self.path.parent.mkdir(parents=True)
        self.path.write_text('{broken')
        with self.assertRaisesRegex(ValueError, 'valid JSON'):
            configure(self.path, self.checkout / 'slack', self.root)
        self.assertEqual(self.path.read_text(), '{broken')
        self.path.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'workspace and commands'):
            load(self.path)

    def test_macos_update_waits_for_launchd_to_release_the_previous_service(self):
        from slack.local.service import install
        completed = lambda code: Mock(returncode=code)
        with patch('slack.local.service.sys.platform', 'darwin'), patch('slack.local.service.Path.home', return_value=self.root), patch('slack.local.service.time.sleep'), patch('slack.local.service.subprocess.run', side_effect=[completed(0), completed(0), completed(5), completed(0)]) as run, contextlib.redirect_stdout(io.StringIO()):
            install(self.checkout / 'cli.py', self.home)
        self.assertEqual(sum(c.args[0][1] == 'bootstrap' for c in run.call_args_list), 2)

    def test_linux_user_service_quotes_paths_and_does_not_export_credentials(self):
        unit = linux_unit(Path(sys.executable), self.root / 'with spaces' / 'cli.py', self.home)
        self.assertIn('with spaces/cli.py" "slack" "serve"', unit)
        self.assertIn('UMask=0077', unit)
        self.assertNotIn('SLACK_', unit)
        with patch('slack.local.service.Path.home', return_value=self.root), patch('slack.local.service.subprocess.run') as run, contextlib.redirect_stdout(io.StringIO()):
            run.return_value.returncode = 0
            install_linux(self.checkout / 'cli.py', self.home)
        self.assertEqual([c.args[0][2] for c in run.call_args_list], ['daemon-reload', 'enable', 'restart'])
        self.assertEqual((self.folder / 'logs/bridge.log').stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
