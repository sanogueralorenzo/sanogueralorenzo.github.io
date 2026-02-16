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
    total_latency_ms: int


@dataclass
class EvalResult:
    summary: EvalSummary
    cases: list[dict[str, Any]]
    text_report_path: Path
    json_report_path: Path


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line_no, line in enumerate(path.read_text(encoding='utf-8').splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        try:
            obj = json.loads(stripped)
        except json.JSONDecodeError as exc:
            raise ValueError(f'Invalid JSONL at {path}:{line_no}: {exc}') from exc
        if not isinstance(obj, dict):
            raise ValueError(f'JSONL row at {path}:{line_no} must be an object')
        rows.append(obj)
    return rows


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', encoding='utf-8') as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + '\n')


def numeric_case_id(case: dict[str, Any], fallback: int) -> int:
    value = case.get('id', fallback)
    try:
        return int(value)
    except (TypeError, ValueError):
        return fallback


def infer_category(case: dict[str, Any]) -> str:
    category = case.get('category')
    if category:
        return str(category)
    input_text = str(case.get('input', ''))
    expected_text = str(case.get('expected', ''))
    return 'clean' if input_text == expected_text else 'noisy'


def split_train_holdout(
    rows: list[dict[str, Any]],
    holdout_mod: int,
    holdout_remainder: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    if holdout_mod <= 1:
        raise ValueError('holdout_mod must be > 1')

    train_rows: list[dict[str, Any]] = []
    holdout_rows: list[dict[str, Any]] = []

    for idx, row in enumerate(rows, start=1):
        key = numeric_case_id(row, idx)
        if key % holdout_mod == holdout_remainder:
            holdout_rows.append(row)
        else:
            train_rows.append(row)

    if not train_rows or not holdout_rows:
        raise ValueError('Invalid split. Adjust holdout_mod / holdout_remainder.')
    return train_rows, holdout_rows


def compare_score(summary: EvalSummary) -> tuple[int, int, int]:
    # Higher is better.
    return (summary.pass_count, -summary.fail_count, -summary.avg_latency_ms)


def winner_by_score(a: EvalSummary, b: EvalSummary) -> str:
    return 'A' if compare_score(a) >= compare_score(b) else 'B'


def category_pass_stats(
    eval_cases: list[dict[str, Any]],
    category_by_id: dict[str, str],
) -> dict[str, dict[str, float]]:
    counters: dict[str, dict[str, float]] = {}
    for case in eval_cases:
        case_id = str(case.get('id'))
        category = category_by_id.get(case_id, 'unknown')
        stats = counters.setdefault(category, {'total': 0.0, 'pass': 0.0})
        stats['total'] += 1.0
        if bool(case.get('passed')):
            stats['pass'] += 1.0

    for stats in counters.values():
        total = stats['total']
        stats['fail'] = total - stats['pass']
        stats['pass_rate'] = (stats['pass'] / total * 100.0) if total else 0.0
    return counters


def parse_eval_result(json_report_path: Path, text_report_path: Path) -> EvalResult:
    payload = json.loads(json_report_path.read_text(encoding='utf-8'))
    summary_payload = payload.get('summary', {})
    summary = EvalSummary(
        total_cases=int(summary_payload.get('total_cases', 0)),
        pass_count=int(summary_payload.get('pass_count', 0)),
        fail_count=int(summary_payload.get('fail_count', 0)),
        pass_rate=float(summary_payload.get('pass_rate', 0.0)),
        avg_latency_ms=int(summary_payload.get('avg_latency_ms', 0)),
        total_latency_ms=int(summary_payload.get('total_latency_ms', 0)),
    )
    return EvalResult(
        summary=summary,
        cases=payload.get('cases', []),
        text_report_path=text_report_path,
        json_report_path=json_report_path,
    )


def run_prompt_eval(
    eval_script: Path,
    prompt_file: Path,
    cases_file: Path,
    report_text_path: Path,
    report_json_path: Path,
    backend: str,
    timeout_sec: int,
    max_cases: int,
    model_path: str | None,
    litertlm_dir: str | None,
    binary_path: str | None,
    skip_setup: bool,
    skip_download: bool,
) -> EvalResult:
    cmd = [
        str(eval_script),
        '--prompt-file',
        str(prompt_file),
        '--cases-file',
        str(cases_file),
        '--report-file',
        str(report_text_path),
        '--json-report-file',
        str(report_json_path),
        '--backend',
        backend,
        '--timeout-sec',
        str(timeout_sec),
        '--max-cases',
        str(max_cases),
        '--no-update',
    ]

    if model_path:
        cmd.extend(['--model-path', model_path])
    if litertlm_dir:
        cmd.extend(['--litertlm-dir', litertlm_dir])
    if binary_path:
        cmd.extend(['--binary-path', binary_path])
    if skip_setup:
        cmd.append('--skip-setup')
    if skip_download:
        cmd.append('--skip-download')

    subprocess.run(cmd, check=True)
    return parse_eval_result(report_json_path, report_text_path)


def strip_challenger_focus(prompt_text: str) -> str:
    marker = '\n\n# Challenger Focus\n'
    if marker in prompt_text:
        return prompt_text.split(marker, 1)[0].strip()
    return prompt_text.strip()


def split_prompt_body_and_input_block(prompt_text: str) -> tuple[str, str]:
    for input_block in ('\n\nUser input:\n{{input}}', '\n\nUser input:\n{input}'):
        if input_block in prompt_text:
            body, _ = prompt_text.split(input_block, 1)
            return body.strip(), input_block
    return prompt_text.strip(), '\n\nUser input:\n{{input}}'


def build_next_challenger_prompt(
    winner_prompt_text: str,
    loser_failure_cases: list[dict[str, Any]],
) -> str:
    base_prompt = strip_challenger_focus(winner_prompt_text)
    body, input_block = split_prompt_body_and_input_block(base_prompt)

    focus_lines = [
        '- Keep all winner constraints exactly as written.',
        '- Fix only what is needed to match expected text exactly.',
        '- Do not introduce broader rewrites or tone changes.',
    ]

    examples: list[str] = []
    for row in loser_failure_cases[:8]:
        examples.append(
            f"{row.get('id')}: input=\"{str(row.get('input', '')).strip()}\" "
            f"expected=\"{str(row.get('expected', '')).strip()}\" "
            f"actual=\"{str(row.get('actual', '')).strip()}\""
        )

    focus_block = ['# Challenger Focus', '', 'Round objective: beat current winner on failing patterns.', '']
    focus_block.append('Priority rules:')
    for line in focus_lines:
        focus_block.append(line)

    if examples:
        focus_block.append('')
        focus_block.append('Failure examples from current loser:')
        for line in examples:
            focus_block.append(f'- {line}')

    return body + '\n\n' + '\n'.join(focus_block).strip() + input_block + '\n'


def build_failure_pack(
    eval_cases: list[dict[str, Any]],
    output_path: Path,
    category_by_id: dict[str, str],
) -> list[dict[str, Any]]:
    failures: list[dict[str, Any]] = []
    for row in eval_cases:
        if bool(row.get('passed')):
            continue
        case_id = str(row.get('id'))
        failures.append(
            {
                'id': row.get('id'),
                'category': category_by_id.get(case_id, 'unknown'),
                'input': row.get('input'),
                'expected': row.get('expected'),
                'actual': row.get('actual'),
                'error': row.get('error'),
                'match': row.get('match'),
            }
        )
    write_jsonl(output_path, failures)
    return failures


def git_head_sha(repo_root: Path) -> str:
    try:
        return subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=str(repo_root), text=True
        ).strip()
    except Exception:  # noqa: BLE001
        return 'unknown'


def format_stats(stats: dict[str, dict[str, float]]) -> dict[str, dict[str, float]]:
    out: dict[str, dict[str, float]] = {}
    for key, value in stats.items():
        out[key] = {
            'total': int(value.get('total', 0.0)),
            'pass': int(value.get('pass', 0.0)),
            'fail': int(value.get('fail', 0.0)),
            'pass_rate': round(float(value.get('pass_rate', 0.0)), 2),
        }
    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        description='A/B prompt evaluator: recommendation-only by default.'
    )
    parser.add_argument('--prompt-a-file', default='scripts/prompt_a.txt')
    parser.add_argument('--prompt-b-file', default='scripts/prompt_b.txt')
    parser.add_argument('--dataset-file', default='scripts/dataset.jsonl')
    parser.add_argument('--eval-script', default='scripts/prompt_eval.sh')
    parser.add_argument('--run-root', default='.cache/prompt_ab')

    parser.add_argument('--max-rounds', type=int, default=1)
    parser.add_argument('--patience', type=int, default=1)
    parser.add_argument('--min-improvement-pass-rate-pp', type=float, default=1.0)
    parser.add_argument('--max-category-drop-pp', type=float, default=3.0)
    parser.add_argument('--use-holdout', action='store_true')
    parser.add_argument('--min-holdout-pass-rate', type=float, default=90.0)
    parser.add_argument('--holdout-mod', type=int, default=5)
    parser.add_argument('--holdout-remainder', type=int, default=0)

    parser.add_argument('--backend', default='auto')
    parser.add_argument('--timeout-sec', type=int, default=30)
    parser.add_argument('--max-cases-train', type=int, default=0)
    parser.add_argument('--max-cases-holdout', type=int, default=0)

    parser.add_argument('--model-path', default='')
    parser.add_argument('--litertlm-dir', default='')
    parser.add_argument('--binary-path', default='')

    parser.add_argument('--always-skip-setup', action='store_true')
    parser.add_argument('--always-skip-download', action='store_true')

    args = parser.parse_args()

    if args.max_rounds <= 0:
        raise ValueError('max-rounds must be > 0')

    repo_root = Path.cwd()
    prompt_a_path = (repo_root / args.prompt_a_file).resolve()
    prompt_b_path = (repo_root / args.prompt_b_file).resolve()
    dataset_path = (repo_root / args.dataset_file).resolve()
    eval_script = (repo_root / args.eval_script).resolve()

    if not prompt_a_path.exists() or not prompt_b_path.exists():
        raise FileNotFoundError('Prompt files not found.')
    if not dataset_path.exists():
        raise FileNotFoundError(f'Dataset file not found: {dataset_path}')
    if not eval_script.exists():
        raise FileNotFoundError(f'Eval script not found: {eval_script}')

    run_root = (repo_root / args.run_root).resolve()
    run_dir = run_root / f"run_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    run_dir.mkdir(parents=True, exist_ok=True)

    all_cases = load_jsonl(dataset_path)
    if args.use_holdout:
        train_cases, holdout_cases = split_train_holdout(
            all_cases,
            holdout_mod=args.holdout_mod,
            holdout_remainder=args.holdout_remainder,
        )
    else:
        train_cases = all_cases
        holdout_cases = []

    split_dir = run_dir / 'splits'
    train_path = split_dir / 'train.jsonl'
    write_jsonl(train_path, train_cases)
    holdout_path: Path | None = None
    if holdout_cases:
        holdout_path = split_dir / 'holdout.jsonl'
        write_jsonl(holdout_path, holdout_cases)

    train_category_by_id = {str(row.get('id')): infer_category(row) for row in train_cases}
    holdout_category_by_id = {str(row.get('id')): infer_category(row) for row in holdout_cases}

    log_path = run_dir / 'round_log.jsonl'
    recommendation_path = run_dir / 'recommendation.md'
    summary_path = run_dir / 'summary.json'

    prepared_runtime = False
    no_improve_rounds = 0
    best_recommendation = 'KEEP_A'

    for round_index in range(1, args.max_rounds + 1):
        round_tag = f'round_{round_index:02d}'
        round_dir = run_dir / round_tag
        round_dir.mkdir(parents=True, exist_ok=True)

        prompt_a_text = prompt_a_path.read_text(encoding='utf-8').strip() + '\n'
        prompt_b_text = prompt_b_path.read_text(encoding='utf-8').strip() + '\n'

        train_a = run_prompt_eval(
            eval_script=eval_script,
            prompt_file=prompt_a_path,
            cases_file=train_path,
            report_text_path=round_dir / 'train_a_report.txt',
            report_json_path=round_dir / 'train_a_report.json',
            backend=args.backend,
            timeout_sec=args.timeout_sec,
            max_cases=args.max_cases_train,
            model_path=args.model_path or None,
            litertlm_dir=args.litertlm_dir or None,
            binary_path=args.binary_path or None,
            skip_setup=(args.always_skip_setup or prepared_runtime),
            skip_download=(args.always_skip_download or prepared_runtime),
        )
        prepared_runtime = True

        train_b = run_prompt_eval(
            eval_script=eval_script,
            prompt_file=prompt_b_path,
            cases_file=train_path,
            report_text_path=round_dir / 'train_b_report.txt',
            report_json_path=round_dir / 'train_b_report.json',
            backend=args.backend,
            timeout_sec=args.timeout_sec,
            max_cases=args.max_cases_train,
            model_path=args.model_path or None,
            litertlm_dir=args.litertlm_dir or None,
            binary_path=args.binary_path or None,
            skip_setup=True,
            skip_download=True,
        )

        train_a_stats = category_pass_stats(train_a.cases, train_category_by_id)
        train_b_stats = category_pass_stats(train_b.cases, train_category_by_id)

        train_winner = winner_by_score(train_a.summary, train_b.summary)
        b_over_a_delta_pass = train_b.summary.pass_count - train_a.summary.pass_count
        b_over_a_delta_pass_rate = train_b.summary.pass_rate - train_a.summary.pass_rate

        threshold_ok = b_over_a_delta_pass_rate >= args.min_improvement_pass_rate_pp

        guardrail_ok = True
        guardrail_reason = 'ok'
        for critical_category in ('clean', 'noisy'):
            if critical_category not in train_a_stats or critical_category not in train_b_stats:
                continue
            drop_pp = train_a_stats[critical_category]['pass_rate'] - train_b_stats[critical_category]['pass_rate']
            if drop_pp > args.max_category_drop_pp:
                guardrail_ok = False
                guardrail_reason = (
                    f'B regressed {critical_category} by {drop_pp:.2f}pp '
                    f'(limit {args.max_category_drop_pp:.2f}pp)'
                )
                break

        holdout_checked = False
        holdout_ok = True
        holdout_winner = 'A'
        holdout_a: EvalResult | None = None
        holdout_b: EvalResult | None = None

        if args.use_holdout and train_winner == 'B' and threshold_ok and guardrail_ok and holdout_path is not None:
            holdout_checked = True
            holdout_a = run_prompt_eval(
                eval_script=eval_script,
                prompt_file=prompt_a_path,
                cases_file=holdout_path,
                report_text_path=round_dir / 'holdout_a_report.txt',
                report_json_path=round_dir / 'holdout_a_report.json',
                backend=args.backend,
                timeout_sec=args.timeout_sec,
                max_cases=args.max_cases_holdout,
                model_path=args.model_path or None,
                litertlm_dir=args.litertlm_dir or None,
                binary_path=args.binary_path or None,
                skip_setup=True,
                skip_download=True,
            )
            holdout_b = run_prompt_eval(
                eval_script=eval_script,
                prompt_file=prompt_b_path,
                cases_file=holdout_path,
                report_text_path=round_dir / 'holdout_b_report.txt',
                report_json_path=round_dir / 'holdout_b_report.json',
                backend=args.backend,
                timeout_sec=args.timeout_sec,
                max_cases=args.max_cases_holdout,
                model_path=args.model_path or None,
                litertlm_dir=args.litertlm_dir or None,
                binary_path=args.binary_path or None,
                skip_setup=True,
                skip_download=True,
            )
            holdout_winner = winner_by_score(holdout_a.summary, holdout_b.summary)
            holdout_ok = holdout_winner == 'B' and holdout_b.summary.pass_rate >= args.min_holdout_pass_rate

        recommend_switch_to_b = (
            train_winner == 'B' and threshold_ok and guardrail_ok and holdout_ok
        )

        if recommend_switch_to_b:
            best_recommendation = 'PROMOTE_B'
            no_improve_rounds = 0
            decision_reason = (
                f"B wins train score, improves by {b_over_a_delta_pass_rate:.2f}pp "
                f"(threshold {args.min_improvement_pass_rate_pp:.2f}pp), and passes guardrails"
                + (' and holdout.' if args.use_holdout else '.')
            )
            loser_cases = train_a.cases
            winner_text = prompt_b_text
        else:
            best_recommendation = 'KEEP_A'
            no_improve_rounds += 1
            if train_winner != 'B':
                decision_reason = 'A wins train score tie-break order (pass, fail, latency).'
            elif not threshold_ok:
                decision_reason = (
                    f"B improvement {b_over_a_delta_pass_rate:.2f}pp is below threshold "
                    f"{args.min_improvement_pass_rate_pp:.2f}pp."
                )
            elif not guardrail_ok:
                decision_reason = f'B rejected by guardrail: {guardrail_reason}'
            else:
                decision_reason = 'B failed holdout promotion rule.'
            loser_cases = train_b.cases
            winner_text = prompt_a_text

        loser_failure_pack_path = round_dir / 'loser_failure_pack.jsonl'
        loser_failures = build_failure_pack(
            eval_cases=loser_cases,
            output_path=loser_failure_pack_path,
            category_by_id=train_category_by_id,
        )

        suggested_next_b = build_next_challenger_prompt(winner_text, loser_failures)
        suggested_next_b_path = round_dir / 'suggested_next_prompt_b.txt'
        suggested_next_b_path.write_text(suggested_next_b, encoding='utf-8')

        mutation_brief = round_dir / 'mutation_brief_for_prompt_b.md'
        mutation_brief.write_text(
            '\n'.join(
                [
                    '# Next Challenger Brief',
                    '',
                    f'- round: {round_index}',
                    f'- recommendation: {best_recommendation}',
                    f'- reason: {decision_reason}',
                    f'- loser_failures: {len(loser_failures)}',
                    '',
                    'Recommendation-only mode: no prompt files were auto-modified.',
                    f'Use this suggested challenger prompt for next run: `{suggested_next_b_path}`',
                ]
            ) + '\n',
            encoding='utf-8',
        )

        holdout_a_stats = (
            category_pass_stats(holdout_a.cases, holdout_category_by_id)
            if holdout_checked and holdout_a is not None
            else {}
        )
        holdout_b_stats = (
            category_pass_stats(holdout_b.cases, holdout_category_by_id)
            if holdout_checked and holdout_b is not None
            else {}
        )

        log_record = {
            'timestamp': datetime.now().isoformat(timespec='seconds'),
            'round': round_index,
            'git_head': git_head_sha(repo_root),
            'protocol': {
                'dataset_file': str(dataset_path),
                'train_split_file': str(train_path),
                'holdout_split_file': str(holdout_path) if holdout_path else None,
                'backend': args.backend,
                'timeout_sec': args.timeout_sec,
                'use_holdout': args.use_holdout,
                'holdout_mod': args.holdout_mod,
                'holdout_remainder': args.holdout_remainder,
                'min_improvement_pass_rate_pp': args.min_improvement_pass_rate_pp,
                'max_category_drop_pp': args.max_category_drop_pp,
                'min_holdout_pass_rate': args.min_holdout_pass_rate,
            },
            'prompts': {
                'prompt_a_path': str(prompt_a_path),
                'prompt_b_path': str(prompt_b_path),
                'prompt_a_text': prompt_a_text,
                'prompt_b_text': prompt_b_text,
            },
            'train': {
                'a_summary': train_a.summary.__dict__,
                'b_summary': train_b.summary.__dict__,
                'a_category_stats': format_stats(train_a_stats),
                'b_category_stats': format_stats(train_b_stats),
                'winner': train_winner,
                'b_over_a_delta_pass': b_over_a_delta_pass,
                'b_over_a_delta_pass_rate_pp': round(b_over_a_delta_pass_rate, 2),
            },
            'holdout': {
                'checked': holdout_checked,
                'winner': holdout_winner,
                'a_summary': holdout_a.summary.__dict__ if holdout_a else None,
                'b_summary': holdout_b.summary.__dict__ if holdout_b else None,
                'a_category_stats': format_stats(holdout_a_stats),
                'b_category_stats': format_stats(holdout_b_stats),
                'ok_for_switch': holdout_ok,
            },
            'guardrail': {
                'ok': guardrail_ok,
                'reason': guardrail_reason,
            },
            'decision': {
                'recommendation': best_recommendation,
                'reason': decision_reason,
            },
            'artifacts': {
                'round_dir': str(round_dir),
                'loser_failure_pack': str(loser_failure_pack_path),
                'suggested_next_prompt_b': str(suggested_next_b_path),
                'mutation_brief': str(mutation_brief),
                'train_a_report_json': str(train_a.json_report_path),
                'train_b_report_json': str(train_b.json_report_path),
                'train_a_report_text': str(train_a.text_report_path),
                'train_b_report_text': str(train_b.text_report_path),
                'holdout_a_report_json': str(round_dir / 'holdout_a_report.json') if holdout_checked else None,
                'holdout_b_report_json': str(round_dir / 'holdout_b_report.json') if holdout_checked else None,
            },
        }

        with log_path.open('a', encoding='utf-8') as f:
            f.write(json.dumps(log_record, ensure_ascii=False) + '\n')

        print(
            f"[{round_tag}] recommendation={best_recommendation} "
            f"A_pass={train_a.summary.pass_count} ({train_a.summary.pass_rate:.2f}%) "
            f"B_pass={train_b.summary.pass_count} ({train_b.summary.pass_rate:.2f}%) "
            f"delta_pp={b_over_a_delta_pass_rate:.2f} "
            f"threshold_pp={args.min_improvement_pass_rate_pp:.2f}"
        )
        print(f"[{round_tag}] reason: {decision_reason}")

        if no_improve_rounds >= args.patience:
            print(f"Stopping early: no-improvement rounds={no_improve_rounds} patience={args.patience}")
            break

    recommendation_lines = [
        '# Prompt Recommendation',
        '',
        f'- recommendation: **{best_recommendation}**',
        '- policy: recommendation-only (no prompt files auto-updated)',
        f'- train dataset: `{train_path}`',
        f'- holdout enabled: `{args.use_holdout}`',
        '',
        '## How To Apply',
        '1. If recommendation is `PROMOTE_B`, copy `scripts/prompt_b.txt` into `scripts/prompt_a.txt` manually.',
        '2. Use `round_*/suggested_next_prompt_b.txt` as the next challenger.',
        '3. Run `scripts/prompt_ab_optimize.sh` again.',
        '',
        '## Key Artifacts',
        f'- round log: `{log_path}`',
        f'- summary: `{summary_path}`',
        f'- recommendation file: `{recommendation_path}`',
    ]
    recommendation_path.write_text('\n'.join(recommendation_lines) + '\n', encoding='utf-8')

    final_summary = {
        'timestamp': datetime.now().isoformat(timespec='seconds'),
        'run_dir': str(run_dir),
        'log_file': str(log_path),
        'recommendation_file': str(recommendation_path),
        'dataset_file': str(dataset_path),
        'train_split_file': str(train_path),
        'holdout_split_file': str(holdout_path) if holdout_path else None,
        'max_rounds': args.max_rounds,
        'patience': args.patience,
        'recommendation': best_recommendation,
        'prompt_a_file': str(prompt_a_path),
        'prompt_b_file': str(prompt_b_path),
        'prompt_a_text': prompt_a_path.read_text(encoding='utf-8'),
        'prompt_b_text': prompt_b_path.read_text(encoding='utf-8'),
    }
    summary_path.write_text(json.dumps(final_summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    print(f'Run complete. artifacts={run_dir}')
    print(f'Recommendation: {best_recommendation}')
    print(f'Recommendation file: {recommendation_path}')
    print(f'Round log: {log_path}')
    print(f'Summary: {summary_path}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
