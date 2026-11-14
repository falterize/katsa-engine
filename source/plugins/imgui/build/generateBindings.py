#!/usr/bin/env python3
"""Regenerates binding/cimgui.ffi.h, the LuaJIT cdef of the cimgui C API.

Needs gcc. Run from anywhere: python3 source/plugins/imgui/build/generateBindings.py
The preprocessor expands cimgui.h (structs and enums included) with small stub headers instead of
the system ones, and the visibility attribute is stripped so ffi.cdef accepts the result.
"""
import pathlib
import re
import subprocess
import tempfile

PLUGIN = pathlib.Path(__file__).resolve().parent.parent
CIMGUI = PLUGIN / 'vendor' / 'cimgui'
OUTPUT = PLUGIN / 'binding' / 'cimgui.ffi.h'

STUBS = {
    'stdio.h': 'typedef struct FILE FILE;\n',
    'stdint.h': (
        'typedef signed char int8_t; typedef unsigned char uint8_t;\n'
        'typedef short int16_t; typedef unsigned short uint16_t;\n'
        'typedef int int32_t; typedef unsigned int uint32_t;\n'
        'typedef long long int64_t; typedef unsigned long long uint64_t;\n'
        'typedef unsigned long size_t; typedef unsigned long uintptr_t; typedef long intptr_t;\n'
    ),
    'stdarg.h': 'typedef __builtin_va_list va_list;\n',
    'stdbool.h': '',
}


def main():
    with tempfile.TemporaryDirectory() as folder:
        for name, text in STUBS.items():
            (pathlib.Path(folder) / name).write_text(text)
        result = subprocess.run(
            ['gcc', '-E', '-P', '-nostdinc', f'-I{folder}', '-DCIMGUI_DEFINE_ENUMS_AND_STRUCTS',
             str(CIMGUI / 'cimgui.h')],
            check=True, capture_output=True, text=True,
        )
    text = result.stdout.replace('extern __attribute__((__visibility__("default"))) ', '')
    text = re.sub(r'\n{3,}', '\n\n', text)
    OUTPUT.write_text(text)
    print(f'wrote {OUTPUT} ({text.count(chr(10))} lines)')


if __name__ == '__main__':
    main()
