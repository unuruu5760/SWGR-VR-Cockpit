"""Builds the one-file UEVR script (English and Korean) and the release packages.

  python build.py                    -> dist/EN/swgr_vr_cockpit.lua, dist/KO/swgr_vr_cockpit.lua
  python build.py release [PAK_DIR]  -> release/
        SWGR-VR-Cockpit-v<ver>-EN.zip / -KO.zip   the whole UEVR profile (rename to
                                                  SWGR-Win64-Shipping.zip for UEVR "Import Config")
        swgr_vr_cockpit-v<ver>-EN.lua / -KO.lua   the script on its own
        SWGR-NoBlackBars-pak-v<ver>.zip           the optional pak mod, if PAK_DIR holds
                                                  zzz_SWGR_NoBlackBars_P.pak/.ucas/.utoc

The script is made of the sections in src/: _header.lua, then every NN_*.lua wrapped in
do ... end (each section gets its own 200-local budget), then _footer.lua."""
import glob, os, shutil, sys, zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
VERSION = '2.0.0'
SCRIPT = 'swgr_vr_cockpit.lua'
PAK = 'zzz_SWGR_NoBlackBars_P'


def build(lang):
    src = os.path.join(ROOT, 'src')
    parts = [open(os.path.join(src, '_header.lua'), encoding='utf-8').read()
             .replace('@LANG@', lang).replace('@VERSION@', VERSION)]
    for f in sorted(glob.glob(os.path.join(src, '[0-9]*.lua'))):
        body = open(f, encoding='utf-8').read().rstrip('\n')
        name = os.path.basename(f)
        parts.append('\n' + '-' * 100 + '\n-- ' + name + '\n' + '-' * 100 + '\ndo\n' + body + '\nend\n')
    parts.append('\n' + open(os.path.join(src, '_footer.lua'), encoding='utf-8').read())
    out = os.path.join(ROOT, 'dist', lang.upper())
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, SCRIPT)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(''.join(parts))
    return path


def zip_dir(base, zpath, prefix=''):
    with zipfile.ZipFile(zpath, 'w', zipfile.ZIP_DEFLATED) as z:
        for dp, _, fs in os.walk(base):
            for f in sorted(fs):
                full = os.path.join(dp, f)
                z.write(full, os.path.join(prefix, os.path.relpath(full, base)))


def release(pak_dir=None):
    out = os.path.join(ROOT, 'release')
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    profile = os.path.join(ROOT, 'profile')
    docs = ['README.md', 'README_KO.md', 'CHANGELOG.md']
    made = []
    for lang in ('en', 'ko'):
        L = lang.upper()
        stage = os.path.join(out, 'stage_' + L)
        os.makedirs(os.path.join(stage, 'scripts'))
        for f in os.listdir(profile):
            shutil.copy(os.path.join(profile, f), stage)
        for f in docs:
            shutil.copy(os.path.join(ROOT, f), stage)
        script = build(lang)
        shutil.copy(script, os.path.join(stage, 'scripts', SCRIPT))
        if lang == 'ko':
            os.makedirs(os.path.join(stage, 'fonts'))
            with open(os.path.join(stage, 'fonts', 'README_FONT.txt'), 'w', encoding='utf-8-sig', newline='\r\n') as fh:
                fh.write('Copy C:\\Windows\\Fonts\\malgun.ttf (Malgun Gothic) into this folder.\n'
                         'UEVR loads menu fonts only from the profile\'s fonts folder; without it the Korean menu text shows as "?".\n'
                         '(The font is part of Windows and is not redistributed here.)\n\n'
                         'C:\\Windows\\Fonts\\malgun.ttf (맑은 고딕)를 이 폴더에 복사하세요.\n'
                         'UEVR 메뉴는 프로필의 fonts 폴더에 있는 글꼴만 읽어요. 없으면 메뉴의 한글이 ? 로 나와요.\n'
                         '(윈도우에 들어 있는 글꼴이라 여기에는 넣지 않았어요.)\n')
        z = os.path.join(out, 'SWGR-VR-Cockpit-v%s-%s.zip' % (VERSION, L))
        zip_dir(stage, z)
        shutil.rmtree(stage)
        lone = os.path.join(out, 'swgr_vr_cockpit-v%s-%s.lua' % (VERSION, L))
        shutil.copy(script, lone)
        made += [z, lone]
    if pak_dir:
        stage = os.path.join(out, 'stage_pak')
        mods = os.path.join(stage, 'Griffin', 'Content', 'Paks', '~mods')
        os.makedirs(mods)
        for ext in ('pak', 'ucas', 'utoc'):
            shutil.copy(os.path.join(pak_dir, PAK + '.' + ext), mods)
        z = os.path.join(out, 'SWGR-NoBlackBars-pak-v%s.zip' % VERSION)
        zip_dir(stage, z)
        shutil.rmtree(stage)
        made.append(z)
    return made


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'release':
        for f in release(sys.argv[2] if len(sys.argv) > 2 else None):
            print(f, os.path.getsize(f))
    else:
        for lang in ('en', 'ko'):
            print(build(lang))
