#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


@dataclass
class EvalSummary:
    total_cases: int
    pass_count: int
    fail_count: int
    pass_rate: float
    avg_latency_ms: int


@dataclass
class EvalResult:
    summary: EvalSummary
    payload: dict[str, Any]
    text_report_path: Path
    json_report_path: Path


def parse_result(json_report_path: Path, text_report_path: Path) -> EvalResult:
    payload = json.loads(json_report_path.read_text(encoding="utf-8"))
    summary_payload = payload.get("summary", {})
    summary = EvalSummary(
        total_cases=int(summary_payload.get("total_cases", 0)),
        pass_count=int(summary_payload.get("pass_count", 0)),
        fail_count=int(summary_payload.get("fail_count", 0)),
        pass_rate=float(summary_payload.get("pass_rate", 0.0)),
        avg_latency_ms=int(summary_payload.get("avg_latency_ms", 0)),
    )
    return EvalResult(
        summary=summary,
        payload=payload,
        text_report_path=text_report_path,
        json_report_path=json_report_path,
    )


def compare_score(summary: EvalSummary) -> tuple[int, int, int]:
    return (summary.pass_count, -summary.fail_count, -summary.avg_latency_ms)


def run_device_eval(
    eval_script: Path,
    serial: str | None,
    prompt_file: Path,
    cases_file: Path,
    report_text_path: Path,
    report_json_path: Path,
    timeout_sec: int,
    package_name: str,
    receiver_component: str,
) -> EvalResult:
    cmd = [
        str(eval_script),
        "--prompt-file",
        str(prompt_file),
        "--cases-file",
        str(cases_file),
        "--report-file",
        str(report_text_path),
        "--json-report-file",
        str(report_json_path),
        "--timeout-sec",
        str(timeout_sec),
        "--package",
        package_name,
        "--receiver-component",
        receiver_component,
    ]
    if serial:
        cmd += ["--serial", serial]
    subprocess.run(cmd, check=True)
    return parse_result(json_report_path=report_json_path, text_report_path=report_text_path)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Android-device A/B prompt evaluator (source-of-truth path)."
    )
    parser.add_argument("--prompt-a-file", default="scripts/prompt_a.txt")
    parser.add_argument("--prompt-b-file", default="scripts/prompt_b.txt")
    parser.add_argument("--dataset-file", default="scripts/dataset.jsonl")
    parser.add_argument("--eval-script", default="scripts/prompt_eval_android.py")
    parser.add_argument("--run-root", default=".cache/prompt_ab_android")
    parser.add_argument("--serial", default="")
    parser.add_argument("--timeout-sec", type=int, default=900)
    parser.add_argument("--min-improvement-pass-rate-pp", type=float, default=1.0)
    parser.add_argument("--max-rounds", type=int, default=1)
    parser.add_argument("--package", default="com.sanogueralorenzo.voice")
    parser.add_argument(
        "--receiver-component",
        default="com.sanogueralorenzo.voice/com.sanogueralorenzo.voice.setup.benchmark.PromptBenchmarkAdbReceiver",
    )
    args = parser.parse_args()

    repo_root = Path.cwd()
    prompt_a_path = (repo_root / args.prompt_a_file).resolve()
    prompt_b_path = (repo_root / args.prompt_b_file).resolve()
    dataset_path = (repo_root / args.dataset_file).resolve()
    eval_script = (repo_root / args.eval_script).resolve()
    if not prompt_a_path.exists() or not prompt_b_path.exists():
        raise FileNotFoundError("Prompt A or B file not found.")
    if not dataset_path.exists():
        raise FileNotFoundError(f"Dataset file not found: {dataset_path}")
    if not eval_script.exists():
        raise FileNotFoundError(f"Eval script not found: {eval_script}")

    run_root = (repo_root / args.run_root).resolve()
    run_dir = run_root / f"run_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    run_dir.mkdir(parents=True, exist_ok=True)

    recommendation = "KEEP_A"
    rounds: list[dict[str, Any]] = []
    for round_index in range(1, max(1, args.max_rounds) + 1):
        round_dir = run_dir / f"round_{round_index:02d}"
        round_dir.mkdir(parents=True, exist_ok=True)

        eval_a = run_device_eval(
            eval_script=eval_script,
            serial=args.serial.strip() or None,
            prompt_file=prompt_a_path,
            cases_file=dataset_path,
            report_text_path=round_dir / "a_report.txt",
            report_json_path=round_dir / "a_report.json",
            timeout_sec=args.timeout_sec,
            package_name=args.package,
            receiver_component=args.receiver_component,
        )
        eval_b = run_device_eval(
            eval_script=eval_script,
            serial=args.serial.strip() or None,
            prompt_file=prompt_b_path,
            cases_file=dataset_path,
            report_text_path=round_dir / "b_report.txt",
            report_json_path=round_dir / "b_report.json",
            timeout_sec=args.timeout_sec,
            package_name=args.package,
            receiver_component=args.receiver_component,
        )

        delta_pass_rate = eval_b.summary.pass_rate - eval_a.summary.pass_rate
        better_by_score = compare_score(eval_b.summary) > compare_score(eval_a.summary)
        if better_by_score and delta_pass_rate >= args.min_improvement_pass_rate_pp:
            recommendation = "PROMOTE_B"
        else:
            recommendation = "KEEP_A"

        rounds.append(
            {
                "round": round_index,
                "recommendation": recommendation,
                "a_summary": eval_a.summary.__dict__,
                "b_summary": eval_b.summary.__dict__,
                "delta_pass_rate_pp": delta_pass_rate,
                "a_report_json": str(eval_a.json_report_path),
                "b_report_json": str(eval_b.json_report_path),
            }
        )

        # Deterministic device benchmark: additional rounds without changing prompts are redundant.
        break

    summary = {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "source_of_truth": "android_device",
        "dataset_file": str(dataset_path),
        "prompt_a_file": str(prompt_a_path),
        "prompt_b_file": str(prompt_b_path),
        "recommendation": recommendation,
        "rounds": rounds,
    }
    summary_path = run_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    recommendation_md = run_dir / "recommendation.md"
    latest_round = rounds[-1]
    recommendation_md.write_text(
        "\n".join(
            [
                "# Android Device A/B Recommendation",
                "",
                "- Source of truth: connected Android device via ADB",
                f"- Recommendation: **{recommendation}**",
                f"- Prompt A pass/fail: {latest_round['a_summary']['pass_count']}/{latest_round['a_summary']['fail_count']}",
                f"- Prompt B pass/fail: {latest_round['b_summary']['pass_count']}/{latest_round['b_summary']['fail_count']}",
                f"- Delta pass-rate (B-A): {latest_round['delta_pass_rate_pp']:.2f} pp",
                "",
                "## Notes",
                "- Mac/host evaluation is optional smoke only and not used for promotion.",
                "- Promotion decisions should be made from this Android-device run output.",
            ]
        ),
        encoding="utf-8",
    )

    print(f"Run complete. artifacts={run_dir}")
    print(f"Recommendation: {recommendation}")
    print(f"Summary JSON: {summary_path}")
    print(f"Recommendation MD: {recommendation_md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
