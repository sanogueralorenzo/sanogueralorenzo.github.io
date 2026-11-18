#!/usr/bin/env python3
"""Restart the production art scene on edits; rebuild only for C# changes."""
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXTENSIONS = {'.cs', '.gdshader', '.tscn', '.csproj', '.godot'}


def snapshot():
    files = list((ROOT / 'source').rglob('*')) + list(ROOT.iterdir())
    result = {}
    for p in files:
        if p.suffix not in EXTENSIONS:
            continue
        try:
            stat = p.stat()
            if p.is_file():
                result[p] = (stat.st_mtime_ns, stat.st_size)
        except FileNotFoundError:  # Editors may replace a file while we scan it.
            pass
    return result


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def main():
    engine, *arguments = sys.argv[1:]
    command = [engine, '--path', str(ROOT), 'art-sample.tscn', *arguments]
    previous = snapshot()
    build_pending = False
    import_pending = False
    child = subprocess.Popen(command, cwd=ROOT)
    print('Preview watching source files. Save to refresh; close the window or Ctrl+C to stop.', flush=True)
    try:
        while True:
            time.sleep(.25)
            current = snapshot()
            if current != previous:
                # Coalesce an editor's burst of writes before rebuilding.
                time.sleep(.25)
                current = snapshot()
                changed = {p for p in current.keys() | previous.keys()
                           if current.get(p) != previous.get(p)}
                import_pending |= current.keys() != previous.keys() or ROOT / 'project.godot' in changed
                build_pending |= any(p.suffix in {'.cs', '.csproj'} for p in changed)
                previous = current
                if build_pending:
                    result = subprocess.run(['dotnet', 'build', '--nologo', '--verbosity', 'quiet'], cwd=ROOT)
                    if result.returncode:
                        print('Build failed; keeping the last preview. Fix and save to retry.', flush=True)
                        continue
                    build_pending = False
                if import_pending:
                    result = subprocess.run([engine, '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'], cwd=ROOT)
                    if result.returncode:
                        print('Import failed; fix resources and restart with --import.', flush=True)
                        return result.returncode
                    import_pending = False
                stop(child)
                child = subprocess.Popen(command, cwd=ROOT)
                print('Preview refreshed.', flush=True)
            elif child.poll() is not None:
                if child.returncode == 75:  # F5: reload unchanged art/resources.
                    child = subprocess.Popen(command, cwd=ROOT)
                else:
                    return child.returncode
    except KeyboardInterrupt:
        return 0
    finally:
        stop(child)


if __name__ == '__main__':
    sys.exit(main())
