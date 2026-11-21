#!/usr/bin/env python3
"""Builds the Katsa book: the table of contents and the previous/next footer of every page.

The order lives in docs/book/book.json (chapters -> pages). Pages stay where they are; this script
writes docs/book/README.md and a navigation block between the `book:nav` markers at the end of each
page. `--check` fails when a file would change or a guide is missing from the book (for CI).
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
BOOK = os.path.join(ROOT, 'docs', 'book')
START, END = '<!-- book:nav -->', '<!-- /book:nav -->'
NAV = re.compile(re.escape(START) + r'.*?' + re.escape(END) + r'\n?', re.S)


def read(path):
    with open(path, newline='', encoding='utf-8') as handle:
        return handle.read()


def title_of(path):
    for line in read(path).splitlines():
        if line.startswith('# '):
            return line[2:].strip()
    return os.path.splitext(os.path.basename(path))[0]


def link(label, target, source):
    relative = os.path.relpath(os.path.join(ROOT, target), os.path.dirname(os.path.join(ROOT, source)))
    return '[%s](%s)' % (label, relative.replace(os.sep, '/'))


def footer(book, chapter_index, page_index, source):
    chapter = book['chapters'][chapter_index]
    flat = [(c, p) for c, ch in enumerate(book['chapters']) for p in range(len(ch['pages']))]
    at = flat.index((chapter_index, page_index))
    parts = []
    if at > 0:
        c, p = flat[at - 1]
        target = book['chapters'][c]['pages'][p]
        parts.append(link('← ' + title_of(os.path.join(ROOT, target)), target, source))
    parts.append(link('Contents', 'docs/book/README.md', source))
    if at + 1 < len(flat):
        c, p = flat[at + 1]
        target = book['chapters'][c]['pages'][p]
        parts.append(link(title_of(os.path.join(ROOT, target)) + ' →', target, source))
    return '%s\n---\n**%s** · chapter %d, %s · page %d of %d\n\n%s\n%s\n' % (
        START,
        book['title'],
        chapter_index + 1,
        chapter['title'],
        page_index + 1,
        len(chapter['pages']),
        ' · '.join(parts),
        END,
    )


def contents(book):
    out = ['# %s\n' % book['title'],
           'Read it from the first page to the last: every page ends with links to the previous and '
           'the next one. Chapters build on each other; the last ones are reference.\n']
    first = book['chapters'][0]['pages'][0]
    out.append('Start here: ' + link(title_of(os.path.join(ROOT, first)), first, 'docs/book/README.md') + '\n')
    for number, chapter in enumerate(book['chapters'], 1):
        out.append('\n## %d. %s\n\n%s\n' % (number, chapter['title'], chapter['about']))
        for page, target in enumerate(chapter['pages'], 1):
            label = title_of(os.path.join(ROOT, target))
            out.append('%d. %s' % (page, link(label, target, 'docs/book/README.md')))
    return '\n'.join(out) + '\n'


def write(path, text, changed, check):
    if os.path.exists(path) and read(path) == text:
        return
    changed.append(os.path.relpath(path, ROOT))
    if not check:
        with open(path, 'w', newline='', encoding='utf-8') as handle:
            handle.write(text)


def main():
    check = '--check' in sys.argv
    book = json.loads(read(os.path.join(BOOK, 'book.json')))
    changed, problems, listed = [], [], set()
    for c, chapter in enumerate(book['chapters']):
        for p, target in enumerate(chapter['pages']):
            path = os.path.join(ROOT, target)
            if not os.path.exists(path):
                problems.append('missing page: ' + target)
                continue
            listed.add(target)
            text = NAV.sub('', read(path)).rstrip('\n') + '\n\n'
            write(path, text + footer(book, c, p, target), changed, check)
    for base, _, files in os.walk(os.path.join(ROOT, 'docs', 'guides')):
        for name in files:
            target = os.path.relpath(os.path.join(base, name), ROOT).replace(os.sep, '/')
            if name.endswith('.md') and target not in listed:
                problems.append('guide not in the book: ' + target)
    write(os.path.join(BOOK, 'README.md'), contents(book), changed, check)
    for line in problems:
        print(line)
    if check and (changed or problems):
        print('Book is stale: ' + ', '.join(changed))
        return 1
    print('book: %d pages, %d updated' % (len(listed), len(changed)))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
