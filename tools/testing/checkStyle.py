"""Check Lua sources against the project style (see AGENTS.md and stylua.toml).

Defaults to the katsa runtime and its tests; the engine and game follow stylua output (see
stylua.toml), which may leave unbreakable lines longer than the limit.
Rules: 100-column lines, single-quoted strings, no one-line function bodies, a blank line between
sibling functions, and a maximum module size. Long-string blocks ([[ ... ]]) are not inspected.
"""

from pathlib import Path
import argparse
import re
import sys

MAX_COLUMNS = 100
MAX_LINES = 700
ONE_LINE_FUNCTION = re.compile(r'^\s*(local\s+)?function\s+[\w.:]+\([^)]*\)\s+\S.*\bend\s*$')
DOUBLE_QUOTED = re.compile(r'"(?:[^"\\\']|\\.)*"')
INLINE_BLOCK = re.compile(r'\b(then|do)\s+\S.*\bend\b\)?,?\s*$|\bfunction\s*\([^)]*\)\s+\S.*\bend\b\)?,?\s*$')
FUNCTION_START = re.compile(r'^(local\s+)?function\s')


def stripStrings(line):
    return re.sub(r"'(?:[^'\\]|\\.)*'", "''", line)


def checkFile(path, maxLines):
    problems = []
    lines = path.read_text(encoding='utf-8').split('\n')
    if len(lines) > maxLines:
        problems.append((1, f'module has {len(lines)} lines (limit {maxLines}); split it by category'))
    inBlock = False
    previous = ''
    for number, line in enumerate(lines, 1):
        if inBlock:
            inBlock = ']]' not in line
            previous = line
            continue
        code = line.split('--', 1)[0] if not re.search(r'[\'"]', line.split('--', 1)[0]) else line
        if re.search(r'\[\[', code) and ']]' not in code.split('[[', 1)[1]:
            inBlock = True
        if len(line) > MAX_COLUMNS:
            problems.append((number, f'line is {len(line)} columns'))
        if ONE_LINE_FUNCTION.match(line):
            problems.append((number, 'one-line function body'))
        if INLINE_BLOCK.search(stripStrings(line.split('--', 1)[0])):
            problems.append((number, 'inline block body'))
        probe = stripStrings(line.split('--', 1)[0])
        if DOUBLE_QUOTED.search(probe) and "'" not in line:
            problems.append((number, 'double-quoted string'))
        if FUNCTION_START.match(line) and previous.strip() not in ('', ) and not previous.lstrip().startswith('--'):
            if previous.strip() == 'end':
                problems.append((number, 'missing blank line before function'))
        previous = line
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        'paths', nargs='*', type=Path, default=[Path('source/katsa'), Path('validation/tests/katsa')]
    )
    parser.add_argument('--max-lines', type=int, default=MAX_LINES)
    args = parser.parse_args()
    total = 0
    for root in args.paths:
        files = [root] if root.is_file() else sorted(root.rglob('*.lua'))
        for path in files:
            for number, message in checkFile(path, args.max_lines):
                print(f'{path}:{number}: {message}')
                total += 1
    print(f'{total} style problem(s)')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
