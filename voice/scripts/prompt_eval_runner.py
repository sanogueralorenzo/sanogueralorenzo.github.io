#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Any


@dataclass
class Case:
    id: str
    input_text: str
    expected: str
    match: str


@dataclass
class CaseResult:
    id: str
    input_text: str
    expected: str
    match: str
    actual: str
    passed: bool
    latency_ms: int
    error: str | None


def load_cases(path: str) -> list[Case]:
    if path.endswith('.json'):
        with open(path, 'r', encoding='utf-8') as f:
            raw = json.load(f)
        if not isinstance(raw, list):
            raise ValueError('JSON cases file must be an array of objects')
    else:
        raw = []
        with open(path, 'r', encoding='utf-8') as f:
            for line_no, line in enumerate(f, start=1):
                stripped = line.strip()
                if not stripped or stripped.startswith('#'):
                    continue
                try:
                    raw.append(json.loads(stripped))
                except json.JSONDecodeError as exc:
                    raise ValueError(f'Invalid JSON on line {line_no}: {exc}') from exc

    cases: list[Case] = []
    for index, item in enumerate(raw, start=1):
        if not isinstance(item, dict):
            raise ValueError(f'Case #{index} must be an object')

        case_id = str(item.get('id', f'case_{index:03d}'))
        input_text = item.get('input')
        expected = item.get('expected')
        match = str(item.get('match', 'exact')).lower().strip()

        if input_text is None or str(input_text).strip() == '':
            raise ValueError(f'Case "{case_id}" is missing "input"')
        if expected is None:
            raise ValueError(f'Case "{case_id}" is missing "expected"')
        if match not in ('exact', 'contains', 'regex'):
            raise ValueError(
                f'Case "{case_id}" has invalid match "{match}". Use exact|contains|regex'
            )

        cases.append(
            Case(
                id=case_id,
                input_text=str(input_text),
                expected=str(expected),
                match=match,
            )
        )
    return cases


def compose_prompt(template: str, input_text: str) -> str:
    if '{{input}}' in template:
        return template.replace('{{input}}', input_text)
    if '{input}' in template:
        return template.replace('{input}', input_text)
    return f"{template.rstrip()}\n\n{input_text}"


def normalize_for_exact(value: str) -> str:
    lines = [line.rstrip() for line in value.strip().splitlines()]
    return '\n'.join(lines).strip()


def compare_output(expected: str, actual: str, mode: str) -> bool:
    if mode == 'exact':
        return normalize_for_exact(actual) == normalize_for_exact(expected)
    if mode == 'contains':
        return expected in actual
    if mode == 'regex':
        return re.search(expected, actual, flags=re.MULTILINE) is not None
    raise ValueError(f'Unsupported match mode: {mode}')


def run_model_once(
    binary_path: str,
    backend: str,
    model_path: str,
    prompt: str,
    timeout_sec: int,
) -> tuple[str, int]:
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', delete=False) as tmp:
        tmp.write(prompt)
        prompt_file = tmp.name

    cmd = [
        binary_path,
        f'--backend={backend}',
        f'--model_path={model_path}',
        f'--input_prompt_file={prompt_file}',
        '--async=false',
        '--benchmark=false',
        '--minloglevel=2',
        '--stderrthreshold=3',
    ]

    started = time.perf_counter()
    try:
        completed = subprocess.run(
            cmd,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
        )
    finally:
        try:
            os.unlink(prompt_file)
        except FileNotFoundError:
            pass

    latency_ms = int((time.perf_counter() - started) * 1000)

    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        stdout = completed.stdout.strip()
        detail = stderr or stdout or f'process exited with code {completed.returncode}'
        raise RuntimeError(detail)

    return completed.stdout.strip(), latency_ms


def write_text_report(
    path: str,
    run_config: dict[str, Any],
    results: list[CaseResult],
    pass_count: int,
    fail_count: int,
    total_latency_ms: int,
) -> None:
    with open(path, 'w', encoding='utf-8') as f:
        f.write('PROMPT EVAL REPORT\n')
        f.write(f"timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"binary: {run_config['binary_path']}\n")
        f.write(f"model_path: {run_config['model_path']}\n")
        f.write(f"backend: {run_config['backend']}\n")
        f.write('sampling: runtime default (no overrides)\n')
        f.write(f"cases_file: {run_config['cases_file']}\n")
        f.write(f"prompt_file: {run_config['prompt_file']}\n")
        f.write('\n')

        for result in results:
            status = 'PASS' if result.passed else 'FAIL'
            f.write(f"[{status}] {result.id} (latency_ms={result.latency_ms}, match={result.match})\n")
            f.write(f"input: {result.input_text}\n")
            f.write(f"expected: {result.expected}\n")
            f.write(f"actual: {result.actual}\n")
            f.write(f"error: {result.error or 'none'}\n")
            f.write('\n')

        total = len(results)
        pass_rate = (pass_count / total * 100.0) if total > 0 else 0.0
        avg_latency = int(total_latency_ms / total) if total > 0 else 0

        f.write('[summary]\n')
        f.write(f'total_cases: {total}\n')
        f.write(f'pass_count: {pass_count}\n')
        f.write(f'fail_count: {fail_count}\n')
        f.write(f'pass_rate: {pass_rate:.2f}%\n')
        f.write(f'avg_latency_ms: {avg_latency}\n')
        f.write(f'total_latency_ms: {total_latency_ms}\n')


def main() -> int:
    parser = argparse.ArgumentParser(description='Run prompt evaluation cases sequentially.')
    parser.add_argument('--binary-path', required=True)
    parser.add_argument('--model-path', required=True)
    parser.add_argument('--prompt-file', required=True)
    parser.add_argument('--cases-file', required=True)
    parser.add_argument('--backend', default='cpu')
    parser.add_argument('--report-file', required=True)
    parser.add_argument('--json-report-file', required=True)
    parser.add_argument('--timeout-sec', type=int, default=240)
    parser.add_argument('--max-cases', type=int, default=0)
    parser.add_argument('--verbose', action='store_true')
    args = parser.parse_args()

    with open(args.prompt_file, 'r', encoding='utf-8') as f:
        prompt_template = f.read().strip()

    if not prompt_template:
        raise ValueError(f'Prompt file is empty: {args.prompt_file}')

    cases = load_cases(args.cases_file)
    if args.max_cases > 0:
        cases = cases[:args.max_cases]

    results: list[CaseResult] = []
    pass_count = 0
    total_latency_ms = 0

    for idx, case in enumerate(cases, start=1):
        if args.verbose:
            print(f'[{idx}/{len(cases)}] running {case.id}', flush=True)

        final_prompt = compose_prompt(prompt_template, case.input_text)

        actual = ''
        passed = False
        latency_ms = 0
        error: str | None = None

        try:
            actual, latency_ms = run_model_once(
                binary_path=args.binary_path,
                backend=args.backend,
                model_path=args.model_path,
                prompt=final_prompt,
                timeout_sec=args.timeout_sec,
            )
            passed = compare_output(case.expected, actual, case.match)
        except Exception as exc:  # noqa: BLE001
            error = str(exc)

        total_latency_ms += latency_ms
        if passed:
            pass_count += 1

        results.append(
            CaseResult(
                id=case.id,
                input_text=case.input_text,
                expected=case.expected,
                match=case.match,
                actual=actual,
                passed=passed,
                latency_ms=latency_ms,
                error=error,
            )
        )

    fail_count = len(results) - pass_count

    run_config = {
        'binary_path': os.path.abspath(args.binary_path),
        'model_path': os.path.abspath(args.model_path),
        'backend': args.backend,
        'prompt_file': os.path.abspath(args.prompt_file),
        'cases_file': os.path.abspath(args.cases_file),
        'timeout_sec': args.timeout_sec,
        'max_cases': args.max_cases,
        'sampling': {
            'mode': 'runtime_default',
            'top_k': None,
            'top_p': None,
            'temperature': None,
            'seed': None,
        },
    }

    report_dir = os.path.dirname(os.path.abspath(args.report_file))
    if report_dir:
        os.makedirs(report_dir, exist_ok=True)
    json_dir = os.path.dirname(os.path.abspath(args.json_report_file))
    if json_dir:
        os.makedirs(json_dir, exist_ok=True)

    write_text_report(
        path=args.report_file,
        run_config=run_config,
        results=results,
        pass_count=pass_count,
        fail_count=fail_count,
        total_latency_ms=total_latency_ms,
    )

    report_payload = {
        'timestamp': datetime.now().isoformat(timespec='seconds'),
        'config': run_config,
        'summary': {
            'total_cases': len(results),
            'pass_count': pass_count,
            'fail_count': fail_count,
            'pass_rate': (pass_count / len(results) * 100.0) if results else 0.0,
            'avg_latency_ms': int(total_latency_ms / len(results)) if results else 0,
            'total_latency_ms': total_latency_ms,
        },
        'cases': [
            {
                'id': r.id,
                'input': r.input_text,
                'expected': r.expected,
                'match': r.match,
                'actual': r.actual,
                'passed': r.passed,
                'latency_ms': r.latency_ms,
                'error': r.error,
            }
            for r in results
        ],
    }

    with open(args.json_report_file, 'w', encoding='utf-8') as f:
        json.dump(report_payload, f, ensure_ascii=False, indent=2)

    print(
        f"Completed {len(results)} cases. pass={pass_count} fail={fail_count} "
        f"report={os.path.abspath(args.report_file)} json={os.path.abspath(args.json_report_file)}"
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
