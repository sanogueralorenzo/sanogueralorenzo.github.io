import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('worker', Path(__file__).parents[1] / 'Resources/worker.py')
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
NOTE = {'title': 'Launch review', 'recap': 'The launch is still a proposal. A date was not agreed.', 'decisions': [], 'actions': [], 'questions': ['When should it launch?']}

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
        parts = w.chunks(text)
        self.assertTrue(all(len(p) <= 18000 for p in parts))
        self.assertEqual(''.join(parts).replace('\n', ''), text.replace('\n', ''))

    def test_retry_reuses_successful_partial_notes(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            text = 'a' * 17000 + '\n' + 'b' * 17000 + '\n' + 'c' * 17000
            calls = []
            def interrupted(source, settings):
                calls.append(source)
                if len(calls) == 2:
                    raise RuntimeError('provider unavailable')
                return NOTE.copy()
            with self.assertRaises(RuntimeError):
                w.summarize(text, {'provider': 'local'}, folder, interrupted)
            self.assertEqual(len(list((folder / 'summaries').glob('*.json'))), 1)
            calls.clear()
            def resumed(source, settings):
                calls.append(source)
                return NOTE.copy()
            result = w.summarize(text, {'provider': 'local'}, folder, resumed)
            self.assertEqual(result['title'], NOTE['title'])
            self.assertFalse(any(source.startswith('a' * 100) for source in calls))
            self.assertTrue(any('c' * 100 in source for source in calls))

    def test_transcript_short_circuits_audio_and_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            w.atomic(folder / 'transcript.txt', 'Preserved transcript')
            # The dependency import is available in the installed test runtime.
            self.assertEqual(w.transcribe(folder, {}), 'Preserved transcript')

    def test_cloud_models_rejected_before_network(self):
        with patch('urllib.request.build_opener', side_effect=AssertionError('network')):
            for model in ('qwen:cloud', 'org/remote', ''):
                with self.assertRaises(ValueError):
                    w.generate('private transcript', {'provider': 'local', 'model': model})

    def test_disguised_remote_model_rejected(self):
        from unittest.mock import MagicMock
        opener = MagicMock()
        response = opener.open.return_value.__enter__.return_value
        response.read.return_value = json.dumps({'remote_host': 'https://ollama.com', 'model_info': {'general.architecture': 'qwen'}}).encode()
        with patch('urllib.request.build_opener', return_value=opener):
            with self.assertRaisesRegex(ValueError, 'local weights'):
                w.generate('private transcript', {'provider': 'local', 'model': 'custom-name'})
        self.assertEqual(opener.open.call_count, 1)  # Metadata only; never submit the transcript.

    def test_empty_transcript_cannot_become_a_note(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'empty'):
                w.summarize('  ', {}, Path(tmp))

    def test_cli_drain_and_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(w.cli_run(['/bin/cat'], 'untrusted source\n', tmp), 'untrusted source\n')
            with self.assertRaises(RuntimeError):
                w.cli_run(['/usr/bin/false'], '', tmp)

if __name__ == '__main__':
    unittest.main()
