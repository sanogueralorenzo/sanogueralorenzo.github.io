import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / 'Resources'))

import notes as w
from files import atomic
from pi_processor import PROVIDERS
from transcription import transcribe
NOTE = {'title': 'Launch review', 'recap': 'The launch is still a proposal. A date was not agreed.', 'decisions': [], 'actions': [], 'questions': ['When should it launch?']}

class FixtureProcessor:
    def __init__(self, callback, provider='openai', budget=18000):
        self.callback = callback
        self.provider, self.model = PROVIDERS[provider]
        self.input_budget = budget

    def generate(self, message):
        synthesis = message.startswith(w.SYNTHESIS)
        source = message[len(w.SYNTHESIS):] if synthesis else message
        return json.dumps(self.callback(source, synthesis))

class WorkerTests(unittest.TestCase):
    def test_empty_sections_and_checkboxes(self):
        text = w.body(NOTE)
        self.assertNotIn('Decisions', text)
        self.assertNotIn('Action items', text)
        self.assertIn('Open questions', text)
        self.assertIn('☐ Jo will send the draft', w.body(dict(NOTE, actions=['Jo will send the draft'])))

    def test_invalid_output_is_not_published(self):
        for value in ({}, dict(NOTE, recap=''), dict(NOTE, decisions='approved'), dict(NOTE, actions=[None])):
            with self.assertRaises(ValueError):
                w.validate(value)

    def test_long_lines_are_not_lost(self):
        text = 'a' * 40001 + '\nlast commitment'
        parts = w.chunks(text, 18000)
        self.assertTrue(all(len(p) <= 18000 for p in parts))
        self.assertEqual(''.join(parts), text)

    def test_retry_reuses_successful_partial_notes(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            text = 'a' * 17000 + '\n' + 'b' * 17000 + '\n' + 'c' * 17000
            calls = []
            def interrupted(source, synthesis):
                calls.append(source)
                if len(calls) == 2:
                    raise RuntimeError('provider unavailable')
                return NOTE.copy()
            with self.assertRaises(RuntimeError):
                w.summarize(text, folder, FixtureProcessor(interrupted))
            self.assertEqual(len(list((folder / 'summaries').glob('*.json'))), 1)
            calls.clear()
            def resumed(source, synthesis):
                calls.append(source)
                return NOTE.copy()
            result = w.summarize(text, folder, FixtureProcessor(resumed))
            self.assertEqual(result['title'], NOTE['title'])
            self.assertFalse(any(source.startswith('a' * 100) for source in calls))
            self.assertTrue(any('c' * 100 in source for source in calls))

    def test_transcript_short_circuits_audio_and_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            atomic(folder / 'transcript.txt', 'Preserved transcript')
            # The dependency import is available in the installed test runtime.
            self.assertEqual(transcribe(folder, {}), 'Preserved transcript')

    def test_local_requires_explicit_remote_choice(self):
        with patch('pi_processor.shutil.which', side_effect=AssertionError('must not start Pi')):
            for provider in ('local', '', None, 'unknown'):
                with self.assertRaisesRegex(ValueError, 'Choose OpenAI or Anthropic'):
                    w.write_note('private transcript', provider, Path('/unused'))

    def test_empty_transcript_cannot_become_a_note(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'empty'):
                w.write_note('  ', 'openai', Path(tmp))

    def test_unicode_and_blank_lines_fit_without_loss(self):
        text = 'é😀漢字\n\n' * 500
        parts = w.chunks(text, 1000)
        self.assertEqual(''.join(parts), text)
        self.assertTrue(all(len(w.prompt(part).encode()) <= 1000 for part in parts))
        source = 'x' * 30000
        self.assertEqual(w.chunks(source, len(w.prompt(source).encode())), [source])

    def test_fitting_transcript_is_one_request_and_cache_tracks_prompt_and_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            calls = []
            def generate(source, synthesis):
                calls.append(source)
                return NOTE.copy()
            folder = Path(tmp)
            text = 'meeting speech ' * 2000
            def run(provider='openai'):
                return w.summarize(text, folder, FixtureProcessor(generate, provider, 100000))
            run(); run()
            self.assertEqual(calls, [text])
            run('anthropic')
            self.assertEqual(len(calls), 2)
            with patch.object(w, 'PROMPT_VERSION', 'changed'):
                run()
            self.assertEqual(len(calls), 3)

    def test_raw_transcript_and_explicit_synthesis(self):
        source = 'Jo: I might ship Friday.\nDo not change these words.'
        self.assertEqual(w.prompt(source), source)
        with tempfile.TemporaryDirectory() as tmp:
            calls = []
            def generate(text, synthesis):
                calls.append((text, synthesis))
                return NOTE.copy()
            text = "\n".join(f"[{i}] {source}" for i in range(150))
            w.summarize(text, Path(tmp), FixtureProcessor(generate, budget=2000))
            self.assertEqual(''.join(text for text, mode in calls if not mode), text)
            self.assertTrue(calls[-1][1])
            self.assertTrue(all(w.prompt(text, mode).startswith(w.SYNTHESIS) for text, mode in calls if mode))

    def test_worker_failure_uses_one_result_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / 'transcript.txt').write_text('')
            (folder / 'model.json').write_text('{}')
            worker = Path(__file__).parents[1] / 'Resources/worker.py'
            result = subprocess.run([sys.executable, str(worker), str(folder), 'openai', str(folder / 'model.json')], capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            self.assertIn('empty', json.loads((folder / 'result.json').read_text())['error'])
            self.assertFalse((folder / 'error.txt').exists())
            self.assertFalse((folder / 'processor.json').exists())
            self.assertTrue((folder / 'transcript.txt').exists())

    def test_worker_lock_preserves_running_job_result(self):
        import fcntl
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / 'result.json').write_text('existing result')
            with (folder / 'processing.lock').open('w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                worker = Path(__file__).parents[1] / 'Resources/worker.py'
                result = subprocess.run([sys.executable, str(worker), str(folder), 'openai', str(folder / 'model.json')], capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 1)
                self.assertEqual((folder / 'result.json').read_text(), 'existing result')

if __name__ == '__main__':
    unittest.main()
