#!/usr/bin/env python3
"""Build Feel4Speed's lean runtime ZIP, or its complete source ZIP with --source.

Both modes use game-root paths without an enclosing wrapper directory. The
runtime contains Lua, scripts, UI assets, the speed shader and the root LICENSE.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path,
                        default=Path(__file__).resolve().parents[3])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source', action='store_true',
                        help='Include documentation, notices and developer tests')
    args = parser.parse_args()
    root = args.root.resolve()
    output = args.output.resolve()
    folders = {'art', 'lua', 'scripts', 'ui'}
    root_documents = {'LICENSE', 'README.md'}
    runtime_required = {
        'LICENSE',
        'lua/common/feel4speed/model.lua',
        'lua/common/feel4speed/dynamics.lua',
        'lua/common/feel4speed/drift.lua',
        'lua/common/feel4speed/cornering.lua',
        'lua/ge/extensions/feel4speed/main.lua',
        'lua/ge/extensions/feel4speed/rpm.lua',
        'lua/ge/extensions/feel4speed/distance.lua',
        'lua/ge/extensions/feel4speed/postfx.lua',
        'lua/ge/extensions/core/cameraModes/feel4speed.lua',
        'lua/ge/extensions/core/input/actions/feel4speed.json',
        'scripts/feel4speed/modScript.lua',
        'ui/modules/apps/Feel4Speed/app.json',
        'ui/modules/apps/Feel4Speed/app.js',
        'ui/modules/apps/Feel4Speed/app-v100.html',
        'ui/modules/apps/Feel4Speed/app-v100.css',
        'ui/modules/apps/Feel4Speed/app.png',
        'art/feel4speed/shaders/feel4speedP.hlsl'
    }
    source_required = runtime_required | {
        'README.md',
        'art/feel4speed/README.txt',
        'art/feel4speed/VALIDATION.txt',
        'art/feel4speed/LICENSE.txt',
        'art/feel4speed/OPEN_SOURCE.txt',
        'art/feel4speed/THIRD_PARTY_NOTICES.txt',
        'art/feel4speed/dev/build_zip.py',
        'art/feel4speed/dev/build_icon.py',
        'art/feel4speed/dev/run_tests.py',
        'art/feel4speed/dev/test_feel4speed.lua',
        'art/feel4speed/dev/test_dynamics.lua',
        'art/feel4speed/dev/test_distance.lua',
        'art/feel4speed/dev/test_rpm.lua',
        'art/feel4speed/dev/test_drift.lua',
        'art/feel4speed/dev/test_cornering.lua',
        'art/feel4speed/dev/test_roll_geometry.lua',
        'art/feel4speed/dev/test_ui.js',
        'art/feel4speed/dev/test_layout.js'
    }
    assert root.is_dir(), f'Mod root does not exist: {root}'
    assert output.suffix.lower() == '.zip', 'Output must be a .zip file'
    source_entries = {}
    for p in sorted(root.rglob('*')):
        relative = p.relative_to(root)
        if '__pycache__' in relative.parts or any(part.startswith('.') for part in relative.parts):
            continue
        # Inspect directory symlinks too; pathlib does not traverse them.
        assert not p.is_symlink(), f'Symlink: {relative.as_posix()}'
        if not p.is_file() or p.resolve() == output:
            continue
        name = relative.as_posix()
        assert name in root_documents or relative.parts[0] in folders, \
            f'Unexpected top-level path or wrapper directory: {name}'
        assert '\\' not in name and '..' not in relative.parts, f'Unsafe ZIP path: {name}'
        assert p.name not in {'orbit.lua', 'camera.lua', 'gameengine.lua'}, \
            f'Stock engine file must not be included: {name}'
        if relative.parts[0] == 'lua':
            assert name.startswith(('lua/common/feel4speed/', 'lua/ge/extensions/feel4speed/')) \
                or name in {'lua/ge/extensions/core/cameraModes/feel4speed.lua',
                            'lua/ge/extensions/core/input/actions/feel4speed.json'}, \
                f'Lua file outside the Feel4Speed namespace: {name}'
        if relative.parts[0] == 'scripts':
            assert name.startswith('scripts/feel4speed/'), f'Unrelated script: {name}'
        if relative.parts[0] == 'ui':
            assert name.startswith('ui/modules/apps/Feel4Speed/'), f'Unrelated UI asset: {name}'
        source_entries[name] = p

    assert 'LICENSE' in source_entries, 'Missing root LICENSE'
    assert 'art/feel4speed/LICENSE.txt' in source_entries, 'Missing source license notice'
    assert source_entries['LICENSE'].read_bytes() == \
        source_entries['art/feel4speed/LICENSE.txt'].read_bytes(), 'License notices differ'
    if args.source:
        entries = source_entries
        required = source_required
    else:
        entries = {name: p for name, p in source_entries.items()
                   if name == 'LICENSE' or name.split('/')[0] in {'lua', 'scripts', 'ui'}
                   or name == 'art/feel4speed/shaders/feel4speedP.hlsl'}
        required = runtime_required
        assert not any('dev' in Path(name).parts or Path(name).name.lower().startswith('readme')
                       for name in entries), 'Runtime ZIP must not contain README or dev files'
    assert required <= entries.keys(), f'Missing: {required - entries.keys()}'

    # Snapshot bytes before writing, so CRC and byte-equality checks refer to
    # precisely the inputs packaged rather than a subsequently edited file.
    payloads = {name: p.read_bytes() for name, p in entries.items()}
    for name, data in payloads.items():
        if name.endswith('.json'):
            json.loads(data)

    def build_bytes():
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_DEFLATED,
                             compresslevel=9) as archive:
            for name, data in payloads.items():
                info = zipfile.ZipInfo(name, date_time=(2026, 10, 10, 0, 0, 0))
                info.create_system = 3
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, data, compresslevel=9)
        return buffer.getvalue()

    archive_bytes = build_bytes()
    assert archive_bytes == build_bytes(), 'ZIP output is not deterministic'
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
        assert archive.testzip() is None, 'CRC verification failed'
        assert archive.namelist() == list(payloads), 'ZIP paths differ or contain duplicates'
        for name, data in payloads.items():
            assert archive.read(name) == data, f'Byte mismatch: {name}'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(archive_bytes)
    assert output.read_bytes() == archive_bytes, 'Written ZIP differs from validated ZIP'
    print(json.dumps({'file': str(output), 'mode': 'source' if args.source else 'runtime',
                      'files': len(payloads), 'bytes': len(archive_bytes),
                      'top_level': sorted({name.split('/')[0] for name in payloads}),
                      'sha256': hashlib.sha256(archive_bytes).hexdigest()}))


if __name__ == '__main__':
    main()
