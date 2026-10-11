#!/usr/bin/env python3
"""Run Feel4Speed's Lua contract tests without a Lua executable or Python deps.

Usage: python3 art/feel4speed/dev/run_tests.py [mod-root]
Uses the system Lua 5.4 shared library. This tests the renderer-independent
contracts and mocked BeamNG integration; it does not launch the game.
"""
from __future__ import annotations

import argparse
import ctypes
import ctypes.util
from pathlib import Path
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path,
                        default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    root = args.root.resolve()
    suite = root / "art/feel4speed/dev/test_feel4speed.lua"
    if not suite.is_file():
        parser.error(f"Test suite not found: {suite}")
    library = ctypes.util.find_library("lua5.4")
    if not library:
        print("Lua 5.4 shared library not found. Install liblua5.4-0.", file=sys.stderr)
        return 2
    lua = ctypes.CDLL(library)
    lua.luaL_newstate.restype = ctypes.c_void_p
    lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lua.luaL_loadfilex.restype = ctypes.c_int
    lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    lua.luaL_loadstring.restype = ctypes.c_int
    lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                             ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
    lua.lua_pcallk.restype = ctypes.c_int
    lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int,
                                 ctypes.POINTER(ctypes.c_size_t)]
    lua.lua_tolstring.restype = ctypes.c_void_p
    lua.lua_close.argtypes = [ctypes.c_void_p]
    state = lua.luaL_newstate()
    if not state:
        print("Could not create Lua state.", file=sys.stderr)
        return 2

    def evaluate(status: int) -> int:
        if status == 0:
            status = lua.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            length = ctypes.c_size_t()
            message = lua.lua_tolstring(state, -1, ctypes.byref(length))
            if message:
                print(ctypes.string_at(message, length.value).decode("utf-8", "replace"),
                      file=sys.stderr)
            else:
                print(f"Lua failed with status {status}", file=sys.stderr)
            return 1
        return 0

    try:
        lua.luaL_openlibs(state)
        # Escape as a Lua short-string literal; never interpolate shell text.
        escaped = str(root).replace("\\", "\\\\").replace('"', '\\"')
        setup = (f'F4S_TEST_ROOT = "{escaped}"; '
                 'package.path = F4S_TEST_ROOT .. "/lua/common/?.lua;" .. '
                 'F4S_TEST_ROOT .. "/lua/?.lua;" .. package.path')
        if evaluate(lua.luaL_loadstring(state, setup.encode())):
            return 1
        return evaluate(lua.luaL_loadfilex(state, str(suite).encode(), None))
    finally:
        lua.lua_close(state)


if __name__ == "__main__":
    raise SystemExit(main())
