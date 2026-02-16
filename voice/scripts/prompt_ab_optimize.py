#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
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
        raise ValueError(
            'Invalid train/holdout split. Adjust holdout_mod and holdout_remainder.'
        )
    return train_rows, holdout_rows


def compare_score(summary: EvalSummary) -> tuple[int, int, int]:
    # Higher is better for all tuple elements.
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
    cases = payload.get('cases', [])
    return EvalResult(
        summary=summary,
        cases=cases,
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
    return parse_eval_result(
        json_report_path=report_json_path,
        text_report_path=report_text_path,
    )


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

    if not loser_failure_cases:
        focus_lines = [
            '- Keep all winner constraints exactly as written.',
            '- Prioritize exact-match outputs and avoid unnecessary rewrites.',
        ]
        examples: list[str] = []
    else:
        focus_lines = [
            '- Keep all winner constraints exactly as written.',
            '- Fix only what is needed to match expected text exactly.',
            '- Avoid deleting meaningful words while removing obvious repeats/fillers.',
            '- Preserve user intent and wording whenever possible.',
        ]
        examples = []
        for row in loser_failure_cases[:8]:
            case_id = row.get('id')
            input_text = str(row.get('input', '')).strip()
            expected_text = str(row.get('expected', '')).strip()
            actual_text = str(row.get('actual', '')).strip()
            examples.append(
                f"{case_id}: input=\"{input_text}\" expected=\"{expected_text}\" actual=\"{actual_text}\""
            )

    focus_block = ['# Challenger Focus', '']
    focus_block.append('Round objective: beat the current winner on failing patterns.')
    focus_block.append('')
    focus_block.append('Priority rules:')
    for line in focus_lines:
        focus_block.append(line)

    if examples:
        focus_block.append('')
        focus_block.append('Failure examples from last loser run:')
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
        out = subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'],
            cwd=str(repo_root),
            text=True,
        ).strip()
        return out
    except Exception:  # noqa: BLE001
        return 'unknown'


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


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
        description='Round-based A/B prompt optimizer with train/holdout and guardrails.'
    )
    parser.add_argument('--prompt-a-file', default='scripts/prompt_a.txt')
    parser.add_argument('--prompt-b-file', default='scripts/prompt_b.txt')
    parser.add_argument('--dataset-file', default='scripts/dataset.jsonl')
    parser.add_argument('--eval-script', default='scripts/prompt_eval.sh')
    parser.add_argument('--run-root', default='.cache/prompt_ab')

    parser.add_argument('--max-rounds', type=int, default=6)
    parser.add_argument('--patience', type=int, default=2)
    parser.add_argument('--min-improvement-cases', type=int, default=1)
    parser.add_argument('--max-category-drop-pp', type=float, default=3.0)
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
    if args.patience <= 0:
        raise ValueError('patience must be > 0')

    repo_root = Path.cwd()
    prompt_a_path = (repo_root / args.prompt_a_file).resolve()
    prompt_b_path = (repo_root / args.prompt_b_file).resolve()
    dataset_path = (repo_root / args.dataset_file).resolve()
    eval_script = (repo_root / args.eval_script).resolve()

    if not prompt_a_path.exists() or not prompt_b_path.exists():
        raise FileNotFoundError('Prompt files not found. Check --prompt-a-file and --prompt-b-file.')
    if not dataset_path.exists():
        raise FileNotFoundError(f'Dataset file not found: {dataset_path}')
    if not eval_script.exists():
        raise FileNotFoundError(f'Eval script not found: {eval_script}')

    run_root = (repo_root / args.run_root).resolve()
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    run_dir = run_root / f'run_{timestamp}'
    run_dir.mkdir(parents=True, exist_ok=True)

    all_cases = load_jsonl(dataset_path)
    train_cases, holdout_cases = split_train_holdout(
        all_cases,
        holdout_mod=args.holdout_mod,
        holdout_remainder=args.holdout_remainder,
    )

    split_dir = run_dir / 'splits'
    train_path = split_dir / 'train.jsonl'
    holdout_path = split_dir / 'holdout.jsonl'
    write_jsonl(train_path, train_cases)
    write_jsonl(holdout_path, holdout_cases)

    train_category_by_id = {
        str(row.get('id')): infer_category(row)
        for row in train_cases
    }
    holdout_category_by_id = {
        str(row.get('id')): infer_category(row)
        for row in holdout_cases
    }

    log_path = run_dir / 'round_log.jsonl'
    summary_path = run_dir / 'summary.json'
    prompt_snapshots_dir = run_dir / 'prompt_snapshots'
    prompt_snapshots_dir.mkdir(parents=True, exist_ok=True)

    prepared_runtime = False
    no_improve_rounds = 0
    promotions = 0

    for round_index in range(1, args.max_rounds + 1):
        round_tag = f'round_{round_index:02d}'
        round_dir = run_dir / round_tag
        round_dir.mkdir(parents=True, exist_ok=True)

        pre_a = prompt_a_path.read_text(encoding='utf-8').strip() + '\n'
        pre_b = prompt_b_path.read_text(encoding='utf-8').strip() + '\n'

        (prompt_snapshots_dir / f'{round_tag}_prompt_a_before.txt').write_text(pre_a, encoding='utf-8')
        (prompt_snapshots_dir / f'{round_tag}_prompt_b_before.txt').write_text(pre_b, encoding='utf-8')

        skip_setup_a = args.always_skip_setup or prepared_runtime
        skip_download_a = args.always_skip_download or prepared_runtime

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
            skip_setup=skip_setup_a,
            skip_download=skip_download_a,
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

        round_winner = winner_by_score(train_a.summary, train_b.summary)
        b_over_a_delta = train_b.summary.pass_count - train_a.summary.pass_count

        b_beats_threshold = b_over_a_delta >= args.min_improvement_cases
        guardrail_ok = True
        guardrail_reason = 'ok'

        for critical_category in ('clean', 'noisy'):
            if critical_category not in train_a_stats or critical_category not in train_b_stats:
                continue
            a_rate = train_a_stats[critical_category]['pass_rate']
            b_rate = train_b_stats[critical_category]['pass_rate']
            if (a_rate - b_rate) > args.max_category_drop_pp:
                guardrail_ok = False
                guardrail_reason = (
                    f'B regressed {critical_category} by {a_rate - b_rate:.2f}pp '
                    f'(limit {args.max_category_drop_pp:.2f}pp)'
                )
                break

        holdout_checked = False
        holdout_a: EvalResult | None = None
        holdout_b: EvalResult | None = None
        holdout_winner = 'A'
        holdout_ok = False

        promote_b = False
        decision_reason = 'A retained on train score.'

        if round_winner == 'B' and b_beats_threshold and guardrail_ok:
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
            holdout_ok = (
                holdout_winner == 'B'
                and holdout_b.summary.pass_rate >= args.min_holdout_pass_rate
            )

            if holdout_ok:
                promote_b = True
                decision_reason = (
                    'B promoted: beat A on train and holdout, and passed holdout threshold.'
                )
            else:
                decision_reason = (
                    'B beat train but failed holdout promotion rule '
                    f'(winner={holdout_winner}, B_holdout_pass_rate={holdout_b.summary.pass_rate:.2f}%).'
                )
        elif round_winner == 'B' and not b_beats_threshold:
            decision_reason = (
                f'B won tie-break but did not clear min improvement '
                f'({b_over_a_delta} < {args.min_improvement_cases}).'
            )
        elif round_winner == 'B' and not guardrail_ok:
            decision_reason = f'B rejected by guardrail: {guardrail_reason}'

        if promote_b:
            promotions += 1
            prompt_a_path.write_text(pre_b, encoding='utf-8')
            winner_for_mutation = pre_b
            loser_failures = build_failure_pack(
                eval_cases=train_a.cases,
                output_path=round_dir / 'loser_failure_pack.jsonl',
                category_by_id=train_category_by_id,
            )
            next_b = build_next_challenger_prompt(winner_for_mutation, loser_failures)
            prompt_b_path.write_text(next_b, encoding='utf-8')
            no_improve_rounds = 0
            mutation_source = 'A_failures'
        else:
            winner_for_mutation = pre_a
            loser_failures = build_failure_pack(
                eval_cases=train_b.cases,
                output_path=round_dir / 'loser_failure_pack.jsonl',
                category_by_id=train_category_by_id,
            )
            next_b = build_next_challenger_prompt(winner_for_mutation, loser_failures)
            prompt_b_path.write_text(next_b, encoding='utf-8')
            no_improve_rounds += 1
            mutation_source = 'B_failures'

        mutation_brief = round_dir / 'mutation_brief_for_prompt_b.md'
        mutation_brief.write_text(
            '\n'.join(
                [
                    '# Next Challenger Brief',
                    '',
                    f'- round: {round_index}',
                    f'- decision: {decision_reason}',
                    f'- mutation_source: {mutation_source}',
                    f'- loser_failures: {len(loser_failures)}',
                    '',
                    'Use `scripts/prompt_b.txt` as the next challenger prompt.',
                    'It was generated from loser-only failures for this round.',
                ]
            )
            + '\n',
            encoding='utf-8',
        )

        post_a = prompt_a_path.read_text(encoding='utf-8').strip() + '\n'
        post_b = prompt_b_path.read_text(encoding='utf-8').strip() + '\n'
        (prompt_snapshots_dir / f'{round_tag}_prompt_a_after.txt').write_text(post_a, encoding='utf-8')
        (prompt_snapshots_dir / f'{round_tag}_prompt_b_after.txt').write_text(post_b, encoding='utf-8')

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
                'holdout_split_file': str(holdout_path),
                'backend': args.backend,
                'timeout_sec': args.timeout_sec,
                'holdout_mod': args.holdout_mod,
                'holdout_remainder': args.holdout_remainder,
                'min_improvement_cases': args.min_improvement_cases,
                'max_category_drop_pp': args.max_category_drop_pp,
                'min_holdout_pass_rate': args.min_holdout_pass_rate,
            },
            'prompt_paths': {
                'prompt_a': str(prompt_a_path),
                'prompt_b': str(prompt_b_path),
            },
            'prompt_text_before': {
                'prompt_a': pre_a,
                'prompt_b': pre_b,
            },
            'prompt_text_after': {
                'prompt_a': post_a,
                'prompt_b': post_b,
            },
            'train': {
                'a_summary': train_a.summary.__dict__,
                'b_summary': train_b.summary.__dict__,
                'a_category_stats': format_stats(train_a_stats),
                'b_category_stats': format_stats(train_b_stats),
                'winner': round_winner,
                'b_over_a_delta_pass': b_over_a_delta,
            },
            'holdout': {
                'checked': holdout_checked,
                'winner': holdout_winner,
                'a_summary': holdout_a.summary.__dict__ if holdout_a else None,
                'b_summary': holdout_b.summary.__dict__ if holdout_b else None,
                'a_category_stats': format_stats(holdout_a_stats),
                'b_category_stats': format_stats(holdout_b_stats),
                'ok_for_promotion': holdout_ok,
            },
            'guardrail': {
                'ok': guardrail_ok,
                'reason': guardrail_reason,
            },
            'decision': {
                'promote_b': promote_b,
                'reason': decision_reason,
                'mutation_source': mutation_source,
            },
            'artifacts': {
                'round_dir': str(round_dir),
                'loser_failure_pack': str(round_dir / 'loser_failure_pack.jsonl'),
                'mutation_brief': str(mutation_brief),
                'train_a_report_json': str(train_a.json_report_path),
                'train_b_report_json': str(train_b.json_report_path),
                'train_a_report_text': str(train_a.text_report_path),
                'train_b_report_text': str(train_b.text_report_path),
                'holdout_a_report_json': str(round_dir / 'holdout_a_report.json') if holdout_checked else None,
                'holdout_b_report_json': str(round_dir / 'holdout_b_report.json') if holdout_checked else None,
            },
        }

        ensure_parent(log_path)
        with log_path.open('a', encoding='utf-8') as f:
            f.write(json.dumps(log_record, ensure_ascii=False) + '\n')

        print(
            f"[{round_tag}] train_winner={round_winner} promote_b={promote_b} "
            f"A_pass={train_a.summary.pass_count} B_pass={train_b.summary.pass_count} "
            f"holdout_checked={holdout_checked} no_improve_rounds={no_improve_rounds}"
        )

        if no_improve_rounds >= args.patience:
            print(
                f"Stopping early: no improvement for {no_improve_rounds} rounds "
                f"(patience={args.patience})."
            )
            break

    final_summary = {
        'timestamp': datetime.now().isoformat(timespec='seconds'),
        'run_dir': str(run_dir),
        'log_file': str(log_path),
        'dataset_file': str(dataset_path),
        'train_split_file': str(train_path),
        'holdout_split_file': str(holdout_path),
        'max_rounds': args.max_rounds,
        'patience': args.patience,
        'promotions': promotions,
        'final_prompt_a_file': str(prompt_a_path),
        'final_prompt_b_file': str(prompt_b_path),
        'final_prompt_a_text': prompt_a_path.read_text(encoding='utf-8'),
        'final_prompt_b_text': prompt_b_path.read_text(encoding='utf-8'),
    }
    summary_path.write_text(json.dumps(final_summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

    print(f'Run complete. artifacts={run_dir}')
    print(f'Round log: {log_path}')
    print(f'Summary: {summary_path}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
