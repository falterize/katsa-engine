"""Rebuild the pinned OimoPhysics Lua module using external Haxe 4.3.7."""

from pathlib import Path
import argparse
import subprocess
import tempfile


def build(haxe):
    root = Path(__file__).resolve().parents[3]
    with tempfile.TemporaryDirectory() as temporary:
        output = Path(temporary) / 'oimo.lua'
        subprocess.run(
            [
                haxe,
                '-cp',
                str(root / 'vendor/oimoPhysics/source'),
                '-cp',
                str(root / 'tools/build/oimo/bridge'),
                '-main',
                'Main',
                '-D',
                'lua-vanilla',
                '-D',
                'luajit',
                '-D',
                'analyzer-optimize',
                '-dce',
                'std',
                '-lua',
                str(output),
            ],
            check=True,
        )
        generated = output.read_text(encoding='utf-8')
        clock = '__lua_lib_luv_Misc = _G.require("luv")'
        assert clock in generated, 'Unexpected Haxe clock binding; review the generated module'
        # The generated runtime only needs a clock. Route it through LÖVE so the
        # game does not acquire an otherwise unused native luv dependency.
        generated = generated.replace(
            clock,
            '__lua_lib_luv_Misc = { gettimeofday = function() '
            'local t = love.timer.getTime(); '
            'return math.floor(t), (t % 1) * 1000000 end }',
        )
        # Isolate Haxe globals while retaining the historical zero-based array
        # adapter used by the hand-written engine facade.
        module = (
            'local environment = setmetatable({}, {__index = _G})\n'
            'environment._G = environment\n'
            'local function initialize()\n' + generated + '\nend\n'
            'setfenv(initialize, environment)\ninitialize()\n'
            'environment.OimoExports.array = function(values)\n'
            ' local array = {}; for i, value in ipairs(values) do array[i-1]=value end\n'
            ' return environment._hx_tab_array(array, #values)\nend\n'
            'return environment.OimoExports\n'
        )
        (root / 'vendor/oimoPhysics/init.lua').write_text(module, encoding='utf-8')
        print('Built vendor/oimoPhysics/init.lua; run love . --test-v104')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--haxe', default='haxe')
    arguments = parser.parse_args()
    build(arguments.haxe)


if __name__ == '__main__':
    main()
