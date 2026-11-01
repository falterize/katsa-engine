"""Run functional tests, a real-time lifecycle soak or a matched physics comparison."""

from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('test', 'soak', 'benchmark'))
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--katsa', default=shutil.which('katsa') or 'katsa')
    parser.add_argument('--output', type=Path, default=Path('validation-logs'))
    parser.add_argument('--idle', type=float, default=60)
    parser.add_argument('--cycles', type=int, default=50)
    parser.add_argument('--hold', type=float, default=0.5)
    parser.add_argument('--warmup', type=float, default=5)
    parser.add_argument('--seconds', type=float, default=30)
    parser.add_argument('--width', type=int, default=1920)
    parser.add_argument('--height', type=int, default=1080)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment.update({
        'KATSA_SOAK_IDLE': str(args.idle), 'KATSA_SOAK_CYCLES': str(args.cycles),
        'KATSA_SOAK_HOLD': str(args.hold), 'KATSA_BENCH_WARMUP': str(args.warmup),
        'KATSA_BENCH_SECONDS': str(args.seconds), 'KATSA_BENCH_WIDTH': str(args.width),
        'KATSA_BENCH_HEIGHT': str(args.height),
    })
    runs = [('jit', '--test'), ('interpreter', '--test')] if args.mode == 'test' else [
        (args.mode, '--test-soak' if args.mode == 'soak' else '--benchmark-physics')
    ]
    for name, argument in runs:
        environment['KATSA_TEST_INTERPRETER'] = '1' if name == 'interpreter' else '0'
        path = args.output / (name + '.log')
        print(f'Running {name}; log: {path.resolve()}', flush=True)
        with path.open('w', encoding='utf-8') as output:
            result = subprocess.run(
                [args.katsa, str(args.project.resolve()), argument], env=environment,
                stdout=output, stderr=subprocess.STDOUT,
                timeout=300 + args.idle + args.cycles * args.hold * 2
                + (args.warmup + args.seconds) * 4,
            )
        log = path.read_text(encoding='utf-8', errors='replace')
        marker = 'BENCHMARK REPORT' if args.mode == 'benchmark' else 'PASSED'
        if result.returncode or marker not in log or 'FAILED' in log:
            print(log[-10000:])
            return result.returncode or 1
        print(log.strip().splitlines()[-1], flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
