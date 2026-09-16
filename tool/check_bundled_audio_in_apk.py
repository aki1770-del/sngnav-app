#!/usr/bin/env python3
"""Check that every clip the offline voice asks Android to open is in the APK.

Why this exists: from 2026-07-12 to 2026-09-16 the Dart side sent
`audio/ja/<id>.wav`, Android opened `flutter_assets/audio/ja/<id>.wav`, and
the APK held the clips one directory deeper. The open failed, the failure was
not logged, the app fell back to the phone's TTS, and every test passed
because every test injected a fake player.

What it joins, each read from its source:
  1. the keys the engine really sends over the `sngnav/bundled_audio` channel,
     recorded by test/voice/bundled_audio_platform_keys_test.dart
     (run it with SNGNAV_BUNDLED_AUDIO_KEYS_OUT=<file>);
  2. the rule MainActivity.kt applies to a key before `assets.openFd`, read
     from the Kotlin source, never assumed;
  3. the entries of a built APK. Each must exist and be STORED, because
     AssetManager.openFd cannot open a compressed entry.

usage: check_bundled_audio_in_apk.py APK KEYS_FILE [MAIN_ACTIVITY_KT]
exit:  0 every key opens | 1 some key would not open | 2 cannot check
"""
import re
import sys
import zipfile
from pathlib import Path

DEFAULT_KT = (Path(__file__).resolve().parent.parent / 'android' / 'app' / 'src'
              / 'main' / 'kotlin' / 'dev' / 'aki1770del' / 'sngnav_app'
              / 'MainActivity.kt')


class CannotCheck(Exception):
    pass


def key_prefix(kt_path):
    """The prefix MainActivity.kt puts before the channel's asset key."""
    if not kt_path.is_file():
        raise CannotCheck(f'{kt_path} not found')
    src = kt_path.read_text(encoding='utf-8')
    rules = re.findall(r'val\s+key\s*=\s*"([^"$]*)\$asset"', src)
    if len(rules) != 1 or 'assets.openFd(key)' not in src:
        raise CannotCheck(
            f'{kt_path.name}: expected exactly one `val key = "<prefix>$asset"` '
            f'passed to `assets.openFd(key)`, found {len(rules)} such line(s). '
            'This check models that line and will not guess the rule.')
    return rules[0]


def check(apk, keys_file, kt_path):
    prefix = key_prefix(kt_path)
    if not keys_file.is_file():
        raise CannotCheck(
            f'key list {keys_file} not found. Produce it with: '
            'SNGNAV_BUNDLED_AUDIO_KEYS_OUT=<file> flutter test '
            'test/voice/bundled_audio_platform_keys_test.dart')
    keys = [k.strip() for k in keys_file.read_text(encoding='utf-8').splitlines()
            if k.strip()]
    if not keys:
        raise CannotCheck(f'key list {keys_file} is empty')
    if not apk.is_file():
        raise CannotCheck(f'APK {apk} not found')
    try:
        with zipfile.ZipFile(apk) as z:
            entries = {i.filename: i for i in z.infolist()}
    except zipfile.BadZipFile as e:
        raise CannotCheck(f'{apk} is not a readable zip: {e}')
    if not entries:
        raise CannotCheck(f'{apk} has no entries')

    clips = [n for n in entries
             if n.startswith('assets/flutter_assets/') and n.endswith('.wav')]
    print(f'APK {apk.name}: {len(entries)} entries, {len(clips)} .wav under '
          'assets/flutter_assets/')
    print(f'rule read from {kt_path.name}: Android opens "{prefix}<key>", '
          f'which is zip entry "assets/{prefix}<key>"')

    by_name = {}
    for n in clips:
        by_name.setdefault(n.rsplit('/', 1)[-1], n)
    missing, compressed = [], []
    for key in keys:
        entry = f'assets/{prefix}{key}'
        info = entries.get(entry)
        if info is None:
            missing.append(entry)
        elif info.compress_type != zipfile.ZIP_STORED:
            compressed.append(entry)

    opened = len(keys) - len(missing) - len(compressed)
    print(f'{len(keys)} keys: {opened} open, {len(missing)} missing, '
          f'{len(compressed)} compressed')
    for entry in missing[:5]:
        near = by_name.get(entry.rsplit('/', 1)[-1])
        hint = f' (a file of that name is at {near})' if near else ''
        print(f'  MISSING     {entry}{hint}')
    for entry in compressed[:5]:
        print(f'  COMPRESSED  {entry} (openFd cannot open a compressed entry)')
    if missing or compressed:
        print('RED: for these phrases the offline voice cannot open its clip '
              'and falls back to the phone\'s TTS.')
        return 1
    print('GREEN: every key the offline voice sends opens in this APK.')
    return 0


def main(argv):
    if len(argv) not in (3, 4):
        print(__doc__)
        return 2
    kt = Path(argv[3]) if len(argv) == 4 else DEFAULT_KT
    try:
        return check(Path(argv[1]), Path(argv[2]), kt)
    except CannotCheck as e:
        print(f'CANNOT CHECK (not a pass): {e}')
        return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
