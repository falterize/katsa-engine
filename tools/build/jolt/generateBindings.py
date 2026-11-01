"""Generate the single-precision LuaJIT C declarations from pinned joltc.h."""

from pathlib import Path
import argparse
import re

parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
directory = Path(__file__).resolve().parent
root = directory.parents[2]
source = (root / 'vendor/joltPhysics/include/joltc.h').read_text()
source = re.sub(
    r'#if defined\(JPH_DOUBLE_PRECISION\).*?#else\n(.*?)#endif', r'\1', source, flags=re.S
)
source = source[source.index('typedef uint32_t JPH_Bool;') :]
source = re.sub(r'^\s*#.*$', '', source, flags=re.M)
source = source.replace('JPH_CAPI ', '').replace('JPH_API_CALL', '')
source = re.sub(r'0b([01]+)', lambda match: str(int(match[1], 2)), source)
source = re.sub(r'\b(float|double)\s+([A-Za-z_]\w*)\s*\[\s*\]', r'\1 *\2', source)
target = root / 'vendor/joltPhysics/include/joltc.ffi.h'
if args.check:
    assert target.read_text() == source, 'C declarations differ from pinned header'
    print('FFI DECLARATIONS MATCH PINNED HEADER')
else:
    target.write_text(source)
    print(target)
