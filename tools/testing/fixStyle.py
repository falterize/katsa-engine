"""Mechanical style fixes for Lua sources: expands one-line functions, separates sibling functions
and wraps over-long call lines at argument boundaries. Run checkStyle.py afterwards for leftovers."""

from pathlib import Path
import argparse
import re
import sys

MAX_COLUMNS = 100
ONE_LINE = re.compile(r'^(\s*)((?:local\s+)?function\s+[\w.:]+\([^)]*\))\s+(\S.*?)\s+end\s*$')
STATEMENT_START = re.compile(
    r'(?<=[)\]\w}\'"]) (?=(?:alive\(|[\w.:]+\(|return\b|local\b|if\b|for\b|self\.|assert\())'
)


def splitStatements(body):
    # Only split when the body clearly holds several statements.
    parts, depth, current, i, quote = [], 0, '', 0, None
    tokens = body
    while i < len(tokens):
        ch = tokens[i]
        if quote:
            current += ch
            if ch == '\\':
                current += tokens[i + 1]
                i += 1
            elif ch == quote:
                quote = None
        elif ch in '\'"':
            quote = ch
            current += ch
        elif ch in '([{':
            depth += 1
            current += ch
        elif ch in ')]}':
            depth -= 1
            current += ch
        elif ch == ' ' and depth == 0 and current and STATEMENT_START.match(tokens, i):
            rest = tokens[i + 1:]
            if re.match(r'(alive\(|[\w.:]+\(|return\b|local\b|self\.|assert\()', rest) and not re.search(
                r'(then|do|else|and|or|not|function\b.*)$', current
            ) and not current.endswith((',', '=', '(', '..')):
                parts.append(current)
                current = ''
            else:
                current += ch
        else:
            current += ch
        i += 1
    parts.append(current)
    return parts


def expandOneLiners(lines):
    out = []
    for line in lines:
        match = ONE_LINE.match(line)
        if match and 'function' not in match.group(3) and ' end' not in match.group(3).replace('end)', ''):
            indent, head, body = match.groups()
            out.append(indent + head)
            for statement in splitStatements(body):
                out.append(indent + '    ' + statement)
            out.append(indent + 'end')
        else:
            out.append(line)
    return out


def separateFunctions(lines):
    out = []
    for line in lines:
        if re.match(r'(local\s+)?function\s', line) and out and out[-1].strip() == 'end':
            out.append('')
        out.append(line)
    return out


def matchParen(text, start):
    depth, quote, i = 0, None, start
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == '\\':
                i += 1
            elif ch == quote:
                quote = None
        elif ch in '\'"':
            quote = ch
        elif ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def topLevelArguments(text):
    args, depth, quote, current, i = [], 0, None, '', 0
    while i < len(text):
        ch = text[i]
        if quote:
            current += ch
            if ch == '\\':
                current += text[i + 1]
                i += 1
            elif ch == quote:
                quote = None
        elif ch in '\'"':
            quote = ch
            current += ch
        elif ch in '([{':
            depth += 1
            current += ch
        elif ch in ')]}':
            depth -= 1
            current += ch
        elif ch == ',' and depth == 0:
            args.append(current.strip())
            current = ''
        else:
            current += ch
        i += 1
    args.append(current.strip())
    return args


def codeParens(line):
    # Positions of '(' outside string literals.
    quote, positions, i = None, [], 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == '\\':
                i += 1
            elif ch == quote:
                quote = None
        elif ch in '\'"':
            quote = ch
        elif ch == '(':
            positions.append(i)
        elif ch == '-' and line[i:i + 2] == '--':
            break
        i += 1
    return positions


def wrapLine(line):
    if len(line) <= MAX_COLUMNS or line.lstrip().startswith('--'):
        return [line]
    indent = re.match(r'\s*', line).group(0)
    # Try each call opening from the left; wrap the first whose arguments can be split.
    for start in codeParens(line):
        end = matchParen(line, start)
        if end < 0:
            continue
        inner = line[start + 1:end]
        args = topLevelArguments(inner)
        if len(args) < 2:
            continue
        head, tail = line[:start + 1], line[end:]
        continuation = indent + '    '
        rows, current = [], ''
        for index, arg in enumerate(args):
            piece = arg + (',' if index < len(args) - 1 else '')
            candidate = (current + ' ' + piece).strip() if current else piece
            first = not rows
            limit = MAX_COLUMNS - len(tail) if index == len(args) - 1 else MAX_COLUMNS
            width = len(head) + len(candidate) if first else len(continuation) + len(candidate)
            if current and width > limit:
                rows.append(current)
                current = piece
            else:
                current = candidate
        rows.append(current)
        if len(rows) < 2:
            continue
        result = [head + rows[0]] if len(head + rows[0]) <= MAX_COLUMNS else None
        if result is None:
            continue
        result += [continuation + row for row in rows[1:]]
        result[-1] += tail
        if all(len(row) <= MAX_COLUMNS for row in result):
            return result
    return [line]


def fixFile(path):
    original = path.read_text(encoding='utf-8')
    lines = original.split('\n')
    # Skip long-string blocks when wrapping.
    out, inBlock = [], False
    for line in lines:
        if inBlock:
            inBlock = ']]' not in line
            out.append(line)
            continue
        if '[[' in line and ']]' not in line.split('[[', 1)[1]:
            inBlock = True
            out.append(line)
            continue
        out.extend(wrapLine(line))
    lines = separateFunctions(expandOneLiners(out))
    text = re.sub(r'\n{3,}', '\n\n', '\n'.join(lines)).rstrip('\n') + '\n'
    if text != original:
        path.write_text(text, encoding='utf-8')
        return True
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='+', type=Path)
    args = parser.parse_args()
    changed = 0
    for root in args.paths:
        files = [root] if root.is_file() else sorted(root.rglob('*.lua'))
        for path in files:
            changed += fixFile(path)
    print(f'{changed} file(s) changed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
