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


INLINE_IF = re.compile(r'^(\s*)((?:else)?if\b.*?\bthen)\s+(\S.*?)(\s+end)?\s*$')


def expandInlineIf(lines):
    # `if c then x end` / `elseif c then x` -> block form.
    out = []
    for line in lines:
        match = INLINE_IF.match(line)
        body = match.group(3) if match else ''
        if match and not re.search(r'\b(then|else|elseif|function|do)\b', body) and not (
            match.group(4) is None and body.rstrip().endswith(('and', 'or', ',', '(', '{'))
        ):
            indent, head, body, closing = match.groups()
            out.append(indent + head)
            for statement in splitStatements(body):
                out.append(indent + '    ' + statement)
            if closing:
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


def wrapComment(line):
    indent = re.match(r'\s*', line).group(0)
    prefix = indent + ('-- ' if not line.lstrip().startswith('---') else '--- ')
    words, rows, current = line.lstrip()[2:].split(), [], ''
    for word in words:
        if current and len(prefix) + len(current) + 1 + len(word) > MAX_COLUMNS:
            rows.append(prefix + current)
            current = word
        else:
            current = (current + ' ' + word).strip()
    rows.append(prefix + current)
    return rows


def wrapString(line):
    # key = 'long string', -> split the literal with a concatenation continuation.
    match = re.match(r"^(\s*(?:[\w.\[\]]+\s*=\s*|return\s+)?)'((?:[^'\\]|\\.)*)'(,?)$", line)
    if not match:
        return None
    head, text, tail = match.groups()
    indent = re.match(r'\s*', line).group(0)
    limit = MAX_COLUMNS - len(head) - 4
    cut = text.rfind(' ', 0, limit)
    if cut <= 0:
        return None
    first, rest = text[:cut + 1], text[cut + 1:]
    rows = [head + "'" + first + "'", indent + "    .. '" + rest + "'" + tail]
    return rows if all(len(r) <= MAX_COLUMNS for r in rows) else None


def wrapList(line):
    # Packed table fields: `A = 1, B = 2,` -> fill lines at the same indent.
    indent = re.match(r'\s*', line).group(0)
    fields = topLevelArguments(line.strip().rstrip(','))
    if len(fields) < 2 or not line.rstrip().endswith(','):
        return None
    rows, current = [], ''
    for field in fields:
        piece = field + ','
        if current and len(indent) + len(current) + 1 + len(piece) > MAX_COLUMNS:
            rows.append(indent + current)
            current = piece
        else:
            current = (current + ' ' + piece).strip()
    rows.append(indent + current)
    return rows if len(rows) > 1 and all(len(r) <= MAX_COLUMNS for r in rows) else None


def splitAssignment(line):
    # `a, b = x, y` -> one statement per target when no target is read on the right-hand side.
    match = re.match(r'^(\s*)(local\s+)?([^=()]+?)\s*=\s*(.+)$', line)
    if not match or '==' in line.split('=', 1)[0] + '=':
        return None
    indent, local, left, right = match.groups()
    targets = topLevelArguments(left)
    values = topLevelArguments(right)
    if len(targets) < 2 or len(targets) != len(values):
        return None
    for target in targets:
        base = re.match(r'[\w.]+', target)
        if base and re.search(r'(?<![\w.])' + re.escape(base.group(0)) + r'\b', right):
            return None
    return [indent + (local or '') + t + ' = ' + v for t, v in zip(targets, values)]


def trailingComment(line):
    # `code -- comment` -> comment moves to its own line above.
    match = re.match(r"^(\s*)(.*?\S)\s+(--\s.*)$", line)
    if match and "'" not in match.group(3) and len(match.group(2)) <= MAX_COLUMNS:
        return [match.group(1) + match.group(3), match.group(1) + match.group(2)]
    return None


def wrapLine(line):
    if len(line) <= MAX_COLUMNS:
        return [line]
    if line.lstrip().startswith('--'):
        return wrapComment(line)
    indent = re.match(r'\s*', line).group(0)
    for strategy in (wrapString, splitAssignment, wrapList):
        rows = strategy(line)
        if rows:
            return rows
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
    rows = trailingComment(line)
    if rows and all(len(r) <= MAX_COLUMNS for r in rows):
        return [r for row in rows for r in wrapLine(row)]
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
    lines = separateFunctions(expandInlineIf(expandOneLiners(out)))
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
