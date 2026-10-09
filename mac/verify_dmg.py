from pathlib import Path
import hashlib, os, plistlib, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
image=root/'dist/Pocket Tank.dmg'
def run(args):
    return subprocess.check_output([str(arg) for arg in args],text=True,stderr=subprocess.PIPE,timeout=90)
print(run(['hdiutil','verify',image]))
with tempfile.TemporaryDirectory(prefix='pocket-installer-check-',dir='/private/tmp') as directory:
    info=plistlib.loads(run(['hdiutil','attach','-nobrowse','-noautoopen','-readonly','-mountpoint',directory,'-plist',image]).encode())
    device=next(item['dev-entry'] for item in info['system-entities'] if 'dev-entry' in item)
    try:
        mount=Path(directory)
        assert os.readlink(mount/'Applications')=='/Applications'
        assert (mount/'.DS_Store').is_file()
        assert (mount/'.background/background.png').is_file()
        assert 'Drag Pocket Tank.app onto Applications' in (mount/'Read Me.txt').read_text()
        app=mount/'Pocket Tank.app'
        print(run(['codesign','--verify','--deep','--strict',app]))
        source=root/'dist/Pocket Tank.app'
        expected={str(p.relative_to(source)) for p in source.rglob('*') if p.is_file() or p.is_symlink()}
        actual={str(p.relative_to(app)) for p in app.rglob('*') if p.is_file() or p.is_symlink()}
        assert actual==expected, 'App bundle file inventory differs'
        for relative in sorted(expected):
            if (source/relative).is_symlink():
                assert (app/relative).is_symlink() and os.readlink(app/relative)==os.readlink(source/relative), relative
            else:
                assert (app/relative).read_bytes()==(source/relative).read_bytes(), relative
        with (app/'Contents/Info.plist').open('rb') as file: assert plistlib.load(file)['CFBundleShortVersionString']=='1.3'
        uninstaller = mount/'Uninstall Pocket Tank.app'
        if (root/'dist/Uninstall Pocket Tank.app').exists():
            assert uninstaller.is_dir()
            print(run(['codesign','--verify','--deep','--strict',uninstaller]))
            relative = 'Contents/MacOS/PocketTankUninstaller'
            assert (uninstaller/relative).read_bytes()==(root/'dist/Uninstall Pocket Tank.app'/relative).read_bytes()
            with (uninstaller/'Contents/Info.plist').open('rb') as file:
                assert plistlib.load(file)['CFBundleIdentifier']=='com.local.pockettank.uninstaller'
            print('PASS: embedded native uninstaller matches the tested signed build; no uninstall was launched.')
        print('PASS: DMG app exactly matches tested v1.3 executable/model/libraries, signature valid, Applications link and installer artwork present.')
    finally:
        print(run(['hdiutil','detach',device]))
print('DMG SHA256:',hashlib.sha256(image.read_bytes()).hexdigest())
