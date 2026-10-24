#!/usr/bin/env python3
"""Focused tests for the installed-reference compatibility runner."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from unittest import mock


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from reference_browser_corpus import (  # noqa: E402
    ApplicationMetadata,
    ClickWindowLease,
    CorpusResult,
    NetworkMetrics,
    arc_launch_command,
    exact_application_process_is_present,
    read_application_metadata,
    run_arc,
    run_click,
    _run_apple_script,
)


def load_network_server_module():
    module_path = REPOSITORY_ROOT / "CrestTestFixtures" / "network-server.py"
    specification = importlib.util.spec_from_file_location("crest_network_server", module_path)
    module = importlib.util.module_from_spec(specification)
    assert specification.loader is not None
    specification.loader.exec_module(module)
    return module


NETWORK_SERVER = load_network_server_module()


class CorpusResultTests(unittest.TestCase):
    def test_complete_31_check_payload_is_normalized(self) -> None:
        result = CorpusResult.from_payload(
            {
                "passed": 31,
                "total": 31,
                "failures": 0,
                "durationMs": 842.4,
                "userAgent": "ReferenceBrowser/1.0",
                "results": [{"name": "Canvas 2D", "passed": True, "detail": ""}],
            }
        )

        self.assertEqual(result.passed, 31)
        self.assertEqual(result.total, 31)
        self.assertEqual(result.failures, 0)
        self.assertTrue(result.succeeded)
        self.assertEqual(result.user_agent, "ReferenceBrowser/1.0")

    def test_inconsistent_summary_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "summary"):
            CorpusResult.from_payload(
                {
                    "passed": 30,
                    "total": 31,
                    "failures": 0,
                    "durationMs": 1,
                    "userAgent": "ReferenceBrowser/1.0",
                    "results": [],
                }
            )


class NetworkMetricsTests(unittest.TestCase):
    def test_tls_fixture_wraps_the_exact_server_socket_and_ephemeral_identity(self) -> None:
        server = mock.Mock()
        original_socket = server.socket
        certificate = pathlib.Path("/owned/certificate.pem")
        private_key = pathlib.Path("/owned/private-key.pem")
        with mock.patch.object(NETWORK_SERVER.ssl, "SSLContext") as context_type:
            NETWORK_SERVER.configure_tls(
                server,
                certificate=certificate,
                private_key=private_key,
            )

        context_type.assert_called_once_with(NETWORK_SERVER.ssl.PROTOCOL_TLS_SERVER)
        context = context_type.return_value
        context.load_cert_chain.assert_called_once_with(
            certfile=str(certificate.resolve()),
            keyfile=str(private_key.resolve()),
        )
        context.wrap_socket.assert_called_once_with(original_socket, server_side=True)
        self.assertIs(server.socket, context.wrap_socket.return_value)

    def test_final_server_metrics_are_persisted_atomically(self) -> None:
        state = NETWORK_SERVER.NetworkFixtureState()
        state.record_request("/physical-offline.html")
        state.record_response_bytes("/physical-offline.html", 4_096)

        with tempfile.TemporaryDirectory() as temporary_directory:
            output = pathlib.Path(temporary_directory) / "final-metrics.json"
            NETWORK_SERVER.write_metrics_snapshot(output, state)
            value = json.loads(output.read_text())
            leftovers = list(output.parent.glob(".final-metrics.json.*.tmp"))

        self.assertEqual(value, state.snapshot())
        self.assertEqual(leftovers, [])

    def test_final_metrics_do_not_recreate_a_removed_task_owner(self) -> None:
        state = NETWORK_SERVER.NetworkFixtureState()
        with tempfile.TemporaryDirectory() as temporary_directory:
            removed_owner = pathlib.Path(temporary_directory) / "removed-owner"
            removed_owner.mkdir()
            output = removed_owner / "final-metrics.json"
            removed_owner.rmdir()

            with self.assertRaises(FileNotFoundError):
                NETWORK_SERVER.write_metrics_snapshot(output, state)

            self.assertFalse(removed_owner.exists())

    def test_network_fixture_server_binds_the_explicit_interface(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = pathlib.Path(temporary_directory)
            with mock.patch.object(
                NETWORK_SERVER.http.server,
                "ThreadingHTTPServer",
            ) as server_type:
                server = NETWORK_SERVER.create_server(
                    host="10.1.20.183",
                    port=18767,
                    directory=directory,
                )

        self.assertIs(server, server_type.return_value)
        self.assertEqual(server_type.call_args.args[0], ("10.1.20.183", 18767))
        self.assertTrue(server.daemon_threads)

    def test_complete_fixture_snapshot_preserves_exact_requests_and_bytes(self) -> None:
        metrics = NetworkMetrics.from_payload(
            {
                "server": "crest-network-fixture-v1",
                "resetAt": 1_785_000_000.0,
                "totalRequests": 3,
                "totalResponseBytes": 12_288,
                "requests": {"/compatibility.html?crestRun=click-1": 1, "/sample.mp4": 2},
                "responseBytes": {
                    "/compatibility.html?crestRun=click-1": 4_096,
                    "/sample.mp4": 8_192,
                },
            }
        )

        self.assertEqual(metrics.total_requests, 3)
        self.assertEqual(metrics.total_response_bytes, 12_288)
        self.assertEqual(metrics.requests["/sample.mp4"], 2)
        self.assertEqual(metrics.response_bytes["/sample.mp4"], 8_192)
        self.assertEqual(
            metrics.as_json(),
            {
                "totalRequests": 3,
                "totalServedFileBytes": 12_288,
                "requests": {
                    "/compatibility.html?crestRun=click-1": 1,
                    "/sample.mp4": 2,
                },
                "servedFileBytes": {
                    "/compatibility.html?crestRun=click-1": 4_096,
                    "/sample.mp4": 8_192,
                },
            },
        )

    def test_inconsistent_fixture_totals_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "request total"):
            NetworkMetrics.from_payload(
                {
                    "server": "crest-network-fixture-v1",
                    "resetAt": 1_785_000_000.0,
                    "totalRequests": 2,
                    "totalResponseBytes": 4_096,
                    "requests": {"/compatibility.html": 1},
                    "responseBytes": {"/compatibility.html": 4_096},
                }
            )


class ApplicationMetadataTests(unittest.TestCase):
    def test_installed_application_metadata_resolves_declared_executable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            application = pathlib.Path(temporary_directory) / "Reference.app"
            contents = application / "Contents"
            executable = contents / "MacOS" / "ReferenceBrowser"
            executable.parent.mkdir(parents=True)
            executable.touch(mode=0o755)
            with (contents / "Info.plist").open("wb") as plist_file:
                plistlib.dump(
                    {
                        "CFBundleName": "Reference",
                        "CFBundleExecutable": "ReferenceBrowser",
                        "CFBundleShortVersionString": "1.2",
                        "CFBundleVersion": "34",
                    },
                    plist_file,
                )

            metadata = read_application_metadata(application)

        self.assertEqual(metadata.name, "Reference")
        self.assertEqual(metadata.version, "1.2")
        self.assertEqual(metadata.build, "34")
        self.assertEqual(metadata.executable, executable.resolve())

    def test_exact_application_process_does_not_match_helpers_or_prefixes(self) -> None:
        executable = pathlib.Path("/Applications/Arc.app/Contents/MacOS/Arc")

        self.assertTrue(
            exact_application_process_is_present(
                executable,
                ["/Applications/Arc.app/Contents/MacOS/Arc"],
            )
        )
        self.assertFalse(
            exact_application_process_is_present(
                executable,
                [
                    "/Applications/Arc.app/Contents/MacOS/Arc --test-profile",
                    "/Applications/Arc.app/Contents/Frameworks/Browser Helper",
                ],
            )
        )


class ArcLaunchCommandTests(unittest.TestCase):
    def test_clean_profile_must_be_owned_by_the_task_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            task_root = pathlib.Path(temporary_directory)
            executable = task_root / "Arc"
            executable.touch()

            with self.assertRaisesRegex(ValueError, "outside"):
                arc_launch_command(
                    executable=executable,
                    profile=task_root.parent / "real-profile",
                    task_root=task_root,
                    url="http://127.0.0.1:8765/compatibility.html",
                )

    def test_clean_profile_command_disables_first_run_and_sync(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            task_root = pathlib.Path(temporary_directory)
            executable = task_root / "Arc"
            executable.touch()
            profile = task_root / "Arc-profile"

            command = arc_launch_command(
                executable=executable,
                profile=profile,
                task_root=task_root,
                url="http://127.0.0.1:8765/compatibility.html?crestRun=arc-1",
            )

        self.assertEqual(command[0], str(executable))
        self.assertIn(f"--user-data-dir={profile.resolve()}", command)
        self.assertIn("--no-first-run", command)
        self.assertIn("--disable-sync", command)
        self.assertEqual(command[-1], "http://127.0.0.1:8765/compatibility.html?crestRun=arc-1")

    def test_clean_arc_run_refuses_to_route_through_an_active_session(self) -> None:
        metadata = ApplicationMetadata(
            name="Arc",
            version="1.0",
            build="1",
            executable=pathlib.Path("/Applications/Arc.app/Contents/MacOS/Arc"),
        )

        with tempfile.TemporaryDirectory() as temporary_directory:
            with mock.patch(
                "reference_browser_corpus.read_application_metadata", return_value=metadata
            ), mock.patch(
                "reference_browser_corpus._application_is_running", return_value=True
            ):
                with self.assertRaisesRegex(RuntimeError, "already running"):
                    run_arc(
                        application=pathlib.Path("/Applications/Arc.app"),
                        task_root=pathlib.Path(temporary_directory),
                        server=mock.Mock(),
                        timeout=1,
                    )


class ClickNavigationTests(unittest.TestCase):
    def test_click_window_lease_rejects_control_characters(self) -> None:
        with self.assertRaisesRegex(ValueError, "invalid accessibility"):
            ClickWindowLease("Incognito-AppWindow-7\nBrowser-AppWindow-1")

    def test_apple_script_timeout_becomes_a_bounded_runner_failure(self) -> None:
        with mock.patch(
            "reference_browser_corpus.subprocess.run",
            side_effect=subprocess.TimeoutExpired(["osascript", "-"], 20),
        ):
            with self.assertRaisesRegex(RuntimeError, "bounded window transaction"):
                _run_apple_script("return 1")


    def test_click_run_refuses_to_share_an_active_installed_session(self) -> None:
        metadata = ApplicationMetadata(
            name="Click",
            version="1.0",
            build="711",
            executable=pathlib.Path("/Applications/Click.app/Contents/MacOS/Click"),
        )

        with mock.patch(
            "reference_browser_corpus.read_application_metadata", return_value=metadata
        ), mock.patch(
            "reference_browser_corpus._application_is_running", return_value=True
        ), mock.patch(
            "reference_browser_corpus._open_click_incognito",
            side_effect=AssertionError("must not touch an active Click session"),
        ):
            with self.assertRaisesRegex(RuntimeError, "already running"):
                run_click(
                    application=pathlib.Path("/Applications/Click.app"),
                    server=mock.Mock(),
                    timeout=1,
                )

    def test_opt_in_running_click_lease_closes_only_its_incognito_window(self) -> None:
        metadata = ApplicationMetadata(
            name="Click",
            version="1.0",
            build="711",
            executable=pathlib.Path("/Applications/Click.app/Contents/MacOS/Click"),
        )
        corpus = CorpusResult(31, 31, 0, 10, "Click/1.0", ())
        network = NetworkMetrics(0, 0, {}, {})
        server = mock.Mock(base_url="http://127.0.0.1:8765")
        server.network_metrics.return_value = network
        lease = ClickWindowLease("Incognito-AppWindow-7")

        with mock.patch(
            "reference_browser_corpus.read_application_metadata", return_value=metadata
        ), mock.patch(
            "reference_browser_corpus._application_is_running", return_value=True
        ), mock.patch(
            "reference_browser_corpus._open_click_incognito", return_value=lease
        ) as open_window, mock.patch(
            "reference_browser_corpus.wait_for_corpus_result", return_value=corpus
        ), mock.patch(
            "reference_browser_corpus._close_click_incognito"
        ) as close_window, mock.patch(
            "reference_browser_corpus._quit_click"
        ) as quit_click, mock.patch(
            "reference_browser_corpus.subprocess.Popen",
            side_effect=AssertionError("must not relaunch a running Click session"),
        ):
            result = run_click(
                application=pathlib.Path("/Applications/Click.app"),
                server=server,
                timeout=1,
                reuse_running_session=True,
            )

        open_window.assert_called_once()
        close_window.assert_called_once_with(lease)
        quit_click.assert_not_called()
        self.assertIn("preserved running Click session", result.isolation)

    def test_opt_in_running_click_reports_an_exact_window_cleanup_failure(self) -> None:
        metadata = ApplicationMetadata(
            name="Click",
            version="1.0",
            build="711",
            executable=pathlib.Path("/Applications/Click.app/Contents/MacOS/Click"),
        )
        corpus = CorpusResult(31, 31, 0, 10, "Click/1.0", ())
        server = mock.Mock(base_url="http://127.0.0.1:8765")
        server.network_metrics.return_value = NetworkMetrics(0, 0, {}, {})
        lease = ClickWindowLease("Incognito-AppWindow-7")

        with mock.patch(
            "reference_browser_corpus.read_application_metadata", return_value=metadata
        ), mock.patch(
            "reference_browser_corpus._application_is_running", return_value=True
        ), mock.patch(
            "reference_browser_corpus._open_click_incognito", return_value=lease
        ), mock.patch(
            "reference_browser_corpus.wait_for_corpus_result", return_value=corpus
        ), mock.patch(
            "reference_browser_corpus._close_click_incognito",
            side_effect=RuntimeError("exact task window remained open"),
        ), mock.patch(
            "reference_browser_corpus._quit_click"
        ) as quit_click:
            with self.assertRaisesRegex(RuntimeError, "task window remained open"):
                run_click(
                    application=pathlib.Path("/Applications/Click.app"),
                    server=server,
                    timeout=1,
                    reuse_running_session=True,
                )

        quit_click.assert_not_called()


class NetworkCorpusResultTests(unittest.TestCase):
    def setUp(self) -> None:
        self.state = NETWORK_SERVER.NetworkFixtureState()
        NETWORK_SERVER.NetworkFixtureHandler.state = self.state
        handler = lambda *args, **kwargs: NETWORK_SERVER.NetworkFixtureHandler(  # noqa: E731
            *args,
            directory=str(REPOSITORY_ROOT / "CrestTestFixtures"),
            **kwargs,
        )
        self.server = NETWORK_SERVER.http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def test_result_round_trip_is_scoped_to_exact_run(self) -> None:
        payload = json.dumps({"passed": 31, "total": 31, "failures": 0}).encode()
        request = urllib.request.Request(
            f"{self.base_url}/__crest_corpus_result__?run=arc-1",
            data=payload,
            method="POST",
            headers={"Content-Type": "application/json"},
        )

        with urllib.request.urlopen(request) as response:
            self.assertEqual(response.status, 204)
        with urllib.request.urlopen(
            f"{self.base_url}/__crest_corpus_result__?run=arc-1"
        ) as response:
            stored = json.load(response)

        self.assertEqual(stored, {"failures": 0, "passed": 31, "total": 31})
        with self.assertRaises(urllib.error.HTTPError) as missing_result:
            urllib.request.urlopen(f"{self.base_url}/__crest_corpus_result__?run=click-1")
        missing_result.exception.close()
        self.assertEqual(missing_result.exception.code, 404)

    def test_oversized_result_is_rejected_without_storage(self) -> None:
        payload = json.dumps({"detail": "x" * 70_000}).encode()
        request = urllib.request.Request(
            f"{self.base_url}/__crest_corpus_result__?run=arc-1",
            data=payload,
            method="POST",
            headers={"Content-Type": "application/json"},
        )

        with self.assertRaises(urllib.error.HTTPError) as oversized_result:
            urllib.request.urlopen(request)

        oversized_result.exception.close()
        self.assertEqual(oversized_result.exception.code, 413)
        self.assertIsNone(self.state.corpus_result("arc-1"))


if __name__ == "__main__":
    unittest.main()
