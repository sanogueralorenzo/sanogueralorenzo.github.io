import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local.config import load
from local.setup import configure, setup, launcher
from local.service import install_linux, linux_unit
from local import paths


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.path = self.root / 'config.json'
        self.data = self.root / 'data'
        self.state = self.root / 'state'
        self.state.mkdir()
        self.checkout = Path(__file__).resolve().parents[1]

    def tearDown(self):
        self.temp.cleanup()

    def test_first_install_discovers_both_clis_and_defaults_to_chat_and_claude(self):
        with patch('local.setup.shutil.which', return_value=sys.executable):
            config = configure(self.path, self.checkout, self.root)
        self.assertEqual(set(config['commands']), {'chat', 'claude'})
        self.assertTrue(config['commands']['chat']['start'][1].endswith('/agents/codex.py'))
        self.assertEqual(config['commands']['claude']['resume'][-1], '{session_id}')
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_rerun_preserves_custom_keywords_projects_and_sessions(self):
        with patch('local.setup.shutil.which', return_value=sys.executable):
            configure(self.path, self.checkout, self.root)
        config = json.loads(self.path.read_text())
        config['commands']['custom'] = config['commands'].pop('chat')
        config['projects'] = {'demo': str(self.root)}
        self.path.write_text(json.dumps(config))
        before = self.path.read_bytes()
        (self.state / 'state.sqlite3').write_bytes(b'existing sessions')
        previous = self.state / 'extension'
        previous.mkdir()
        (previous / 'bridge-pairing.json').write_text('synthetic-expired-bootstrap')
        (self.state / 'pairing.json').write_text('synthetic-obsolete-key')
        saved_key = self.data / 'slack/pairing.json'
        saved_key.parent.mkdir(parents=True)
        saved_key.write_text('synthetic-current-key')
        with patch('local.setup.launcher', return_value=self.root / 'slack-hook'), patch('local.setup.install') as install, patch('local.setup.health', return_value={'paired': True}), contextlib.redirect_stdout(io.StringIO()) as output:
            setup(self.path, self.state, self.data, self.checkout, self.root)
        install.assert_called_once_with(self.checkout / 'bridge.py', self.path, self.state, self.data)
        self.assertFalse(previous.exists())
        self.assertFalse((self.state / 'pairing.json').exists())
        self.assertEqual(saved_key.read_text(), 'synthetic-current-key')
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual((self.state / 'state.sqlite3').read_bytes(), b'existing sessions')
        self.assertIn('Existing browser pairing', output.getvalue())

    def test_first_install_builds_private_extension_without_printing_a_secret(self):
        with patch('local.setup.shutil.which', return_value=sys.executable), patch('local.setup.launcher', return_value=self.root / 'slack-hook'), patch('local.setup.install'), patch('local.setup.health', return_value={'paired': False}), contextlib.redirect_stdout(io.StringIO()) as output:
            setup(self.path, self.state, self.data, self.checkout, self.root)
        self.assertIn('Load unpacked', output.getvalue())
        self.assertIn('no code to copy', output.getvalue())
        extension = self.data / 'extension'
        self.assertIn(str(extension), output.getvalue())
        self.assertFalse(extension.is_relative_to(self.checkout.parents[2]))
        self.assertTrue((extension / 'manifest.json').is_file())
        self.assertTrue((extension / 'slack/extension/background.mjs').is_file())
        self.assertFalse((extension / 'slack/local').exists())
        self.assertFalse((extension / 'slack/tests').exists())
        self.assertEqual(extension.stat().st_mode & 0o777, 0o700)
        self.assertEqual((extension / 'manifest.json').stat().st_mode & 0o777, 0o600)

    def test_generated_extension_rejects_a_folder_inside_the_repository(self):
        from local.extension import prepare
        with self.assertRaisesRegex(ValueError, 'outside the public repository'):
            prepare(self.checkout, self.checkout / 'private-state')

    def test_launcher_executes_from_any_directory_with_explicit_configuration(self):
        with patch('local.setup.bin_root', return_value=self.root / 'home with spaces/bin'):
            path = launcher(self.path, self.state, self.data, self.checkout)
        import subprocess
        result = subprocess.run([str(path), '--help'], cwd=self.root, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('install,serve,status', result.stdout)
        self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        self.assertIn(str(self.data), path.read_text())

    def test_xdg_overrides_and_relative_values_do_not_move_files_into_the_checkout(self):
        values = {name: str(self.root / name) for name in ['XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CONFIG_HOME', 'XDG_BIN_HOME']}
        with patch.dict('os.environ', values):
            self.assertEqual(paths.data_root(), Path(values['XDG_DATA_HOME']) / 'browser-hooks')
            self.assertEqual(paths.state_root(), Path(values['XDG_STATE_HOME']) / 'browser-hooks/slack')
            self.assertEqual(paths.config_path(), Path(values['XDG_CONFIG_HOME']) / 'browser-hooks/slack.json')
            self.assertEqual(paths.bin_root(), Path(values['XDG_BIN_HOME']))
        with patch.dict('os.environ', {name: 'relative' for name in values}), patch('local.paths.Path.home', return_value=self.root):
            self.assertEqual(paths.data_root(), self.root / '.local/share/browser-hooks')
            self.assertEqual(paths.state_root(), self.root / '.local/state/browser-hooks/slack')
            self.assertEqual(paths.config_path(), self.root / '.config/browser-hooks/slack.json')
            self.assertEqual(paths.bin_root(), self.root / '.local/bin')

    def test_missing_clis_and_bad_config_have_actionable_errors_without_overwriting(self):
        with patch('local.setup.shutil.which', return_value=None), self.assertRaisesRegex(ValueError, 'Install and sign in'):
            configure(self.path, self.checkout, self.root)
        self.assertFalse(self.path.exists())
        self.path.write_text('{broken')
        with self.assertRaisesRegex(ValueError, 'valid JSON'):
            configure(self.path, self.checkout, self.root)
        self.assertEqual(self.path.read_text(), '{broken')
        self.path.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'workspace and commands'):
            load(self.path)

    def test_macos_update_waits_for_launchd_to_release_the_previous_service(self):
        from local.service import install
        completed = lambda code: Mock(returncode=code)
        with patch('local.service.sys.platform', 'darwin'), patch('local.service.Path.home', return_value=self.root), patch('local.service.time.sleep'), patch('local.service.subprocess.run', side_effect=[completed(0), completed(0), completed(5), completed(0)]) as run, contextlib.redirect_stdout(io.StringIO()):
            install(self.checkout / 'bridge.py', self.path, self.state, self.data)
        self.assertEqual(sum(c.args[0][1] == 'bootstrap' for c in run.call_args_list), 2)

    def test_linux_user_service_quotes_paths_and_does_not_export_credentials(self):
        unit = linux_unit(Path(sys.executable), self.root / 'with spaces' / 'bridge.py', self.path, self.state, self.data)
        self.assertIn('with spaces/bridge.py"', unit)
        self.assertIn('UMask=0077', unit)
        self.assertNotIn('SLACK_', unit)
        with patch('local.service.Path.home', return_value=self.root), patch('local.service.subprocess.run') as run, contextlib.redirect_stdout(io.StringIO()):
            run.return_value.returncode = 0
            install_linux(self.checkout / 'bridge.py', self.path, self.state, self.data)
        self.assertEqual([c.args[0][2] for c in run.call_args_list], ['daemon-reload', 'enable', 'restart'])
        self.assertEqual((self.state / 'bridge.log').stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
