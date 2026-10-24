#!/usr/bin/env python3
"""Focused tests for Crest's isolated signed-Release soak harness."""

from __future__ import annotations

import contextlib
import io
import pathlib
import sys
import tempfile
import unittest
from unittest import mock


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "Scripts"))

from crest_release_soak import (  # noqa: E402
    GPUTraceMetricSeries,
    GPUTraceReport,
    GPUTraceTable,
    ProcessFootprint,
    ReleaseSoakSample,
    collect_gpu_trace_report,
    gpu_trace_command,
    gpu_trace_export_command,
    main,
    parse_gpu_metric_table,
    parse_arguments,
    parse_footprint_output,
    parse_web_content_process_ids,
    performance_state_paths,
    prepare_application,
    process_selection_description,
    release_build_command,
    select_owned_gpu_process_id,
    summarize_samples,
    validate_owned_path,
    _report,
)


class ReleaseBuildCommandTests(unittest.TestCase):
    def test_release_build_uses_an_owned_cache_and_dedicated_crest_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            task_root = pathlib.Path(temporary_directory)
            derived_data = task_root / "DerivedData"

            command = release_build_command(
                repository_root=REPOSITORY_ROOT,
                task_root=task_root,
                derived_data=derived_data,
            )

        self.assertIn("-configuration", command)
        self.assertEqual(command[command.index("-configuration") + 1], "Release")
        self.assertEqual(
            command[command.index("-derivedDataPath") + 1],
            str(derived_data.resolve()),
        )
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER=com.pauldavis.crest.performance-soak", command)
        self.assertIn("PRODUCT_NAME=Crest Performance Soak", command)
        self.assertIn(
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CREST_PERFORMANCE_HARNESS",
            command,
        )

    def test_generated_paths_must_be_descendants_of_the_task_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            task_root = pathlib.Path(temporary_directory)

            self.assertEqual(
                validate_owned_path(task_root, task_root / "DerivedData"),
                (task_root / "DerivedData").resolve(),
            )
            with self.assertRaisesRegex(ValueError, "outside"):
                validate_owned_path(task_root, task_root.parent / "shared-cache")
            with self.assertRaisesRegex(ValueError, "root itself"):
                validate_owned_path(task_root, task_root)

    def test_prebuilt_application_is_verified_without_starting_another_build(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            task_root = pathlib.Path(temporary_directory)
            application = task_root / "Crest Performance Soak.app"
            application.mkdir()

            with (
                mock.patch("crest_release_soak._verify_performance_application") as verify,
                mock.patch("crest_release_soak._build_release") as build,
            ):
                prepared = prepare_application(
                    repository_root=REPOSITORY_ROOT,
                    task_root=task_root,
                    derived_data=task_root / "DerivedData",
                    prebuilt_application=application,
                )

        self.assertEqual(prepared, application.resolve())
        verify.assert_called_once_with(application.resolve())
        build.assert_not_called()

    def test_cleanup_scope_includes_only_the_dedicated_container_and_scripts(self) -> None:
        paths = performance_state_paths()
        rendered = {str(path) for path in paths}

        self.assertIn(
            str(
                pathlib.Path.home()
                / "Library"
                / "Containers"
                / "com.pauldavis.crest.performance-soak"
            ),
            rendered,
        )
        self.assertIn(
            str(
                pathlib.Path.home()
                / "Library"
                / "Application Scripts"
                / "com.pauldavis.crest.performance-soak"
            ),
            rendered,
        )
        self.assertNotIn(
            str(pathlib.Path.home() / "Library" / "Containers" / "com.pauldavis.crest"),
            rendered,
        )


class FootprintParserTests(unittest.TestCase):
    def test_auxiliary_footprint_values_are_parsed_as_exact_bytes(self) -> None:
        measurement = parse_footprint_output(
            """
            Auxiliary data:
                phys_footprint: 43828136 B
                phys_footprint_peak: 68256656 B
            """
        )

        self.assertEqual(measurement.current_bytes, 43_828_136)
        self.assertEqual(measurement.peak_bytes, 68_256_656)

    def test_missing_peak_is_rejected_instead_of_reported_as_zero(self) -> None:
        with self.assertRaisesRegex(ValueError, "peak"):
            parse_footprint_output("phys_footprint: 43828136 B")

    def test_declared_web_content_pids_are_exact_positive_and_deduplicated(self) -> None:
        process_ids = parse_web_content_process_ids(
            """
            unrelated=71
            CREST_PERFORMANCE_WEB_CONTENT_PID=420
            CREST_PERFORMANCE_WEB_CONTENT_PID=0
            CREST_PERFORMANCE_WEB_CONTENT_PID=-1
            CREST_PERFORMANCE_WEB_CONTENT_PID=420
            CREST_PERFORMANCE_WEB_CONTENT_PID=421 trailing
            CREST_PERFORMANCE_WEB_CONTENT_PID=422
            """
        )

        self.assertEqual(process_ids, {420, 422})


class GPUTraceTests(unittest.TestCase):
    def test_trace_collection_exports_owned_tables_and_requires_numeric_gpu_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            task_root = pathlib.Path(temporary_directory)
            trace = task_root / "WebKitGPU.trace"
            trace.mkdir()
            (trace / "data.run").write_bytes(b"trace-data")

            def export_table(command: list[str], **_: object) -> mock.Mock:
                xpath = command[command.index("--xpath") + 1]
                schema = xpath.split("@schema='", 1)[1].split("'", 1)[0]
                output = pathlib.Path(command[-1])
                if schema == "metal-perf-overview-process-metric":
                    rows = """
                      <row>
                        <fixed-decimal fmt="17.5"/>
                        <metal-performance-overview-process-metric-name fmt="GPU Utilization"/>
                      </row>
                    """
                else:
                    rows = ""
                output.write_text(
                    f"<trace-query-result><node><schema name=\"{schema}\"/>{rows}</node></trace-query-result>",
                    encoding="utf-8",
                )
                return mock.Mock(returncode=0, stdout="", stderr="")

            with mock.patch("crest_release_soak.subprocess.run", side_effect=export_table) as run:
                report = collect_gpu_trace_report(
                    task_root=task_root,
                    trace=trace,
                    gpu_process_id=842,
                    duration=8,
                )

        self.assertEqual(report.process_id, 842)
        self.assertEqual(report.trace_bytes, len(b"trace-data"))
        self.assertEqual(len(report.tables), 1)
        self.assertEqual(report.tables[0].series[0].name, "GPU Utilization")
        self.assertEqual(run.call_count, 5)

    def test_trace_collection_failure_reports_each_exported_schema_shape(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            task_root = pathlib.Path(temporary_directory)
            trace = task_root / "WebKitGPU.trace"
            trace.mkdir()
            (trace / "data.run").write_bytes(b"trace-data")

            def export_empty_table(command: list[str], **_: object) -> mock.Mock:
                xpath = command[command.index("--xpath") + 1]
                schema = xpath.split("@schema='", 1)[1].split("'", 1)[0]
                pathlib.Path(command[-1]).write_text(
                    f"<trace-query-result><node><schema name=\"{schema}\"/></node></trace-query-result>",
                    encoding="utf-8",
                )
                return mock.Mock(returncode=0, stdout="", stderr="")

            with (
                mock.patch("crest_release_soak.subprocess.run", side_effect=export_empty_table),
                self.assertRaisesRegex(
                    RuntimeError,
                    "metal-perf-overview-process-metric: 0 rows, 0 numeric series",
                ),
            ):
                collect_gpu_trace_report(
                    task_root=task_root,
                    trace=trace,
                    gpu_process_id=842,
                    duration=8,
                )

    def test_cli_forwards_the_requested_gpu_trace_duration_to_the_real_soak(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            output = pathlib.Path(temporary_directory) / "report.json"
            with mock.patch(
                "crest_release_soak.run_soak",
                return_value={"status": "captured"},
            ) as run_soak:
                exit_code = main(
                    [
                        "--active-duration",
                        "12",
                        "--idle-duration",
                        "2",
                        "--sample-interval",
                        "1",
                        "--tab-count",
                        "4",
                        "--gpu-trace-duration",
                        "8",
                        "--output",
                        str(output),
                    ]
                )

        self.assertEqual(exit_code, 0)
        self.assertEqual(run_soak.call_args.kwargs["gpu_trace_duration"], 8)

    def test_release_report_preserves_exact_gpu_process_and_metric_evidence(self) -> None:
        samples = [
            ReleaseSoakSample(
                elapsed_seconds=0,
                phase="active",
                processes=(ProcessFootprint(1, "main", 100, 120),),
            ),
            ReleaseSoakSample(
                elapsed_seconds=2,
                phase="idle",
                processes=(ProcessFootprint(1, "main", 90, 120),),
            ),
        ]
        gpu_trace = GPUTraceReport(
            process_id=842,
            duration_seconds=8,
            trace_bytes=24_000_000,
            tables=(
                GPUTraceTable(
                    schema="metal-perf-overview-process-metric",
                    row_count=2,
                    series=(GPUTraceMetricSeries("GPU Utilization", (25.0, 50.0)),),
                ),
            ),
        )
        server = mock.Mock()
        server.network_metrics.return_value.as_json.return_value = {"requests": {}}

        report = _report(
            active_duration=12,
            idle_duration=2,
            sample_interval=1,
            tab_count=4,
            build_source="built",
            samples=samples,
            server=server,
            gpu_trace=gpu_trace,
        )

        self.assertEqual(report["gpuTrace"], gpu_trace.as_json())
        self.assertTrue(report["generatedAt"].endswith("+00:00"))

    def test_trace_report_preserves_exact_target_and_table_evidence(self) -> None:
        report = GPUTraceReport(
            process_id=842,
            duration_seconds=10,
            trace_bytes=24_000_000,
            tables=(
                GPUTraceTable(
                    schema="metal-perf-overview-process-metric",
                    row_count=2,
                    series=(GPUTraceMetricSeries("GPU Utilization", (25.0, 50.0)),),
                ),
            ),
        )

        self.assertEqual(
            report.as_json(),
            {
                "template": "Game Performance Overview",
                "targetRole": "task-owned WebKit GPU XPC",
                "targetProcessIdentifier": 842,
                "durationSeconds": 10,
                "traceBytes": 24_000_000,
                "tables": [
                    {
                        "schema": "metal-perf-overview-process-metric",
                        "rowCount": 2,
                        "series": [
                            {
                                "name": "GPU Utilization",
                                "sampleCount": 2,
                                "minimum": 25.0,
                                "maximum": 50.0,
                                "mean": 37.5,
                            }
                        ],
                    }
                ],
            },
        )

    def test_gpu_trace_duration_must_fit_inside_the_active_phase(self) -> None:
        parsed = parse_arguments(
            [
                "--active-duration",
                "30",
                "--idle-duration",
                "5",
                "--gpu-trace-duration",
                "10",
            ]
        )

        self.assertEqual(parsed.gpu_trace_duration, 10)
        parser_error = io.StringIO()
        with (
            contextlib.redirect_stderr(parser_error),
            self.assertRaises(SystemExit),
        ):
            parse_arguments(
                [
                    "--active-duration",
                    "10",
                    "--gpu-trace-duration",
                    "11",
                ]
            )
        self.assertIn(
            "GPU trace duration must fit inside the active phase.",
            parser_error.getvalue(),
        )

    def test_trace_targets_only_the_exact_owned_gpu_process(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            task_root = pathlib.Path(temporary_directory)
            trace = task_root / "WebKitGPU.trace"

            command = gpu_trace_command(
                task_root=task_root,
                trace=trace,
                gpu_process_id=842,
                duration=12,
            )

        self.assertEqual(
            command,
            [
                "xcrun",
                "xctrace",
                "record",
                "--template",
                "Game Performance Overview",
                "--attach",
                "842",
                "--time-limit",
                "12s",
                "--output",
                str(trace.resolve()),
                "--no-prompt",
                "--quiet",
            ],
        )

    def test_trace_rejects_an_unowned_path_or_invalid_measurement(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            task_root = pathlib.Path(temporary_directory)

            with self.assertRaisesRegex(ValueError, "outside"):
                gpu_trace_command(
                    task_root=task_root,
                    trace=task_root.parent / "WebKitGPU.trace",
                    gpu_process_id=842,
                    duration=12,
                )
            with self.assertRaisesRegex(ValueError, "process"):
                gpu_trace_command(
                    task_root=task_root,
                    trace=task_root / "WebKitGPU.trace",
                    gpu_process_id=0,
                    duration=12,
                )
            with self.assertRaisesRegex(ValueError, "duration"):
                gpu_trace_command(
                    task_root=task_root,
                    trace=task_root / "WebKitGPU.trace",
                    gpu_process_id=842,
                    duration=0,
                )

    def test_trace_export_is_scoped_to_an_owned_metric_table(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            task_root = pathlib.Path(temporary_directory)
            trace = task_root / "WebKitGPU.trace"
            output = task_root / "gpu-state.xml"

            command = gpu_trace_export_command(
                task_root=task_root,
                trace=trace,
                output=output,
                schema="metal-perf-overview-gpu-state-metric",
            )

            with self.assertRaisesRegex(ValueError, "unsupported"):
                gpu_trace_export_command(
                    task_root=task_root,
                    trace=trace,
                    output=output,
                    schema="time-sample' or @schema='kdebug",
                )

        self.assertEqual(command[:4], ["xcrun", "xctrace", "export", str(trace.resolve())])
        self.assertEqual(
            command[command.index("--xpath") + 1],
            "/trace-toc/run[@number='1']/data/table[@schema='metal-perf-overview-gpu-state-metric']",
        )
        self.assertEqual(command[-2:], ["--output", str(output.resolve())])

    def test_exactly_one_owned_gpu_process_is_required(self) -> None:
        self.assertEqual(
            select_owned_gpu_process_id({701: "networking", 702: "gpu", 703: "web-content"}),
            702,
        )
        with self.assertRaisesRegex(RuntimeError, "no task-owned WebKit GPU"):
            select_owned_gpu_process_id({701: "networking", 703: "web-content"})
        with self.assertRaisesRegex(RuntimeError, "multiple task-owned WebKit GPU"):
            select_owned_gpu_process_id({702: "gpu", 704: "gpu"})

    def test_metric_table_groups_numeric_samples_by_instruments_name(self) -> None:
        table = parse_gpu_metric_table(
            """
            <trace-query-result>
              <node>
                <schema name="metal-perf-overview-process-metric"/>
                <row>
                  <start-time fmt="1.0 ms"/>
                  <fixed-decimal fmt="42.5"/>
                  <metal-performance-overview-process-metric-name fmt="GPU Utilization"/>
                </row>
                <row>
                  <start-time fmt="2.0 ms"/>
                  <fixed-decimal fmt="57.5"/>
                  <metal-performance-overview-process-metric-name fmt="GPU Utilization"/>
                </row>
                <row>
                  <start-time fmt="3.0 ms"/>
                  <fixed-decimal fmt="8.0"/>
                  <metal-performance-overview-process-metric-name fmt="Renderer Utilization"/>
                </row>
              </node>
            </trace-query-result>
            """,
            schema="metal-perf-overview-process-metric",
        )

        self.assertIsInstance(table, GPUTraceTable)
        self.assertEqual(table.row_count, 3)
        self.assertEqual(
            table.as_json()["series"],
            [
                {
                    "name": "GPU Utilization",
                    "sampleCount": 2,
                    "minimum": 42.5,
                    "maximum": 57.5,
                    "mean": 50.0,
                },
                {
                    "name": "Renderer Utilization",
                    "sampleCount": 1,
                    "minimum": 8.0,
                    "maximum": 8.0,
                    "mean": 8.0,
                },
            ],
        )


class ReleaseSoakSummaryTests(unittest.TestCase):

    def test_summary_uses_simultaneous_aggregate_samples_not_summed_process_peaks(self) -> None:
        samples = [
            ReleaseSoakSample(
                elapsed_seconds=0,
                phase="active",
                processes=(
                    ProcessFootprint(10, "main", 100, 200),
                    ProcessFootprint(11, "web-content", 120, 300),
                ),
            ),
            ReleaseSoakSample(
                elapsed_seconds=30,
                phase="active",
                processes=(
                    ProcessFootprint(10, "main", 110, 210),
                    ProcessFootprint(12, "web-content", 150, 400),
                ),
            ),
            ReleaseSoakSample(
                elapsed_seconds=60,
                phase="idle",
                processes=(
                    ProcessFootprint(10, "main", 105, 210),
                    ProcessFootprint(12, "web-content", 130, 400),
                ),
            ),
            ReleaseSoakSample(
                elapsed_seconds=90,
                phase="idle",
                processes=(
                    ProcessFootprint(10, "main", 103, 210),
                    ProcessFootprint(12, "web-content", 125, 400),
                ),
            ),
        ]

        summary = summarize_samples(samples)

        self.assertEqual(summary["sampleHighWaterBytes"], 260)
        self.assertEqual(summary["activeHighWaterBytes"], 260)
        self.assertEqual(summary["idleHighWaterBytes"], 235)
        self.assertEqual(summary["idleStartBytes"], 235)
        self.assertEqual(summary["idleEndBytes"], 228)
        self.assertEqual(summary["idleDeltaBytes"], -7)
        self.assertEqual(summary["sampleCount"], 4)


if __name__ == "__main__":
    unittest.main()
