#!/usr/bin/env python3
"""Build a personal-use app; vendor Homebrew dylibs so it runs without Homebrew."""
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'dist/Downloader.app'
HELPERS = APP / 'Contents/Helpers'
CACHE = ROOT / '.tools'
def run(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()

os.chdir(ROOT)
run('sh', 'scripts/build.sh')
if APP.exists(): shutil.rmtree(APP)
HELPERS.mkdir(parents=True, exist_ok=True)
(APP / 'Contents/MacOS').mkdir(exist_ok=True)
CACHE.mkdir(exist_ok=True)
binary = ROOT / '.build/local/Downloader'
shutil.copy2(binary, APP / 'Contents/MacOS/Downloader')
(APP / 'Contents/Frameworks').mkdir(exist_ok=True)
shutil.copy2(ROOT / '.build/local/libDownloadCore.dylib', APP / 'Contents/Frameworks/libDownloadCore.dylib')
run('codesign', '--force', '--sign', '-', APP / 'Contents/Frameworks/libDownloadCore.dylib')
with (APP / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(dict(CFBundleExecutable='Downloader', CFBundleIdentifier='local.steventswu.Downloader', CFBundleName='Downloader', CFBundlePackageType='APPL', CFBundleShortVersionString='1.1.0', CFBundleVersion='2', LSMinimumSystemVersion='13.0', LSUIElement=True, NSHighResolutionCapable=True), f)

# Resolve the release once; verify the executable against that release's checksum.
import json
release = json.load(urllib.request.urlopen('https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'))
tag = release['tag_name']
base = 'https://github.com/yt-dlp/yt-dlp/releases/download/' + tag + '/'
target = CACHE / ('yt-dlp-' + tag)
if not target.exists():
    urllib.request.urlretrieve(base + 'yt-dlp_macos', target)
sums = urllib.request.urlopen(base + 'SHA2-256SUMS').read().decode()
expected = next(s.split()[0] for s in sums.splitlines() if s.split()[-1] == 'yt-dlp_macos')
assert hashlib.sha256(target.read_bytes()).hexdigest() == expected, 'yt-dlp checksum mismatch'
shutil.copy2(target, HELPERS / 'yt-dlp'); (HELPERS / 'yt-dlp').chmod(0o755)

copied = {}
def vendor(source, name=None):
    source = Path(source).resolve()
    if source in copied: return copied[source]
    dest = HELPERS / (name or source.name)
    if dest.exists() and dest.name in copied.values(): raise RuntimeError('dylib filename collision')
    shutil.copy2(source, dest); dest.chmod(0o755); copied[source] = dest.name
    for row in run('otool', '-L', source).splitlines()[1:]:
        dep = row.strip().split(' (')[0]
        if dep.startswith(('/opt/homebrew/', '/usr/local/')):
            child = vendor(dep)
            run('install_name_tool', '-change', dep, '@loader_path/' + child, dest)
    if dest.suffix == '.dylib': run('install_name_tool', '-id', '@loader_path/' + dest.name, dest)
    run('codesign', '--force', '--sign', '-', dest)
    return dest.name
for name in ('ffmpeg', 'ffprobe', 'deno'):
    source = shutil.which(name)
    if not source: raise RuntimeError('Build machine requires ' + name)
    vendor(source, name)
run('clang', '-mmacosx-version-min=13.0', ROOT / 'scripts/process-launcher.c', '-o', HELPERS / 'process-launcher')
run('codesign', '--force', '--sign', '-', HELPERS / 'process-launcher')
resources = APP / 'Contents/Resources'; resources.mkdir(exist_ok=True)
(resources / 'Dependencies.txt').write_text('yt-dlp ' + tag + '\n' + run(shutil.which('ffmpeg'), '-version').splitlines()[0] + '\n' + run(shutil.which('deno'), '--version').splitlines()[0] + '\n\nBundled library sources:\n' + '\n'.join(str(p) for p in copied) + '\n')
licenses = resources / 'Licenses'; licenses.mkdir(exist_ok=True)
brew = shutil.which('brew')
if not brew: raise RuntimeError('The build machine requires Homebrew')
prefix = lambda formula: Path(run(brew, '--prefix', formula))
license_files = [
    ('FFmpeg-GPLv3.txt', prefix('ffmpeg') / 'COPYING.GPLv3'),
    ('FFmpeg-GPLv2.txt', prefix('ffmpeg') / 'COPYING.GPLv2'),
    ('FFmpeg-LGPLv3.txt', prefix('ffmpeg') / 'COPYING.LGPLv3'),
    ('FFmpeg-LGPLv2.1.txt', prefix('ffmpeg') / 'COPYING.LGPLv2.1'),
    ('Deno-LICENSE.txt', prefix('deno') / 'LICENSE.md'),
    ('x264-COPYING.txt', prefix('x264') / 'COPYING'),
    ('x265-COPYING.txt', prefix('x265') / 'COPYING'),
]
for name, source in license_files:
    source = Path(source)
    if source.exists(): shutil.copy2(source, licenses / name)
shutil.copy2(ROOT / 'LICENSE', licenses / 'Downloader-MIT.txt')
shutil.copy2(ROOT / 'THIRD_PARTY_NOTICES.md', resources / 'THIRD_PARTY_NOTICES.md')
run('codesign', '--force', '--sign', '-', APP)
run('codesign', '--verify', '--deep', '--strict', APP)
print(APP)
