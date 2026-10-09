#!/usr/bin/env python3
"""Create and verify a Pocket Tank drag-to-Applications installer disk image."""
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, plistlib, re, shutil, subprocess, tempfile, time
ROOT=pathlib.Path(__file__).resolve().parents[1]
DEFAULT_APP=ROOT/'dist/Pocket Tank.app'
DEFAULT_OUTPUT=ROOT/'dist/Pocket Tank.dmg'

def run(args, *, timeout=120):
    result=subprocess.run([str(x) for x in args],check=True,capture_output=True,text=True,timeout=timeout)
    return result.stdout

def detach(device):
    try: run(['hdiutil','detach',device],timeout=30)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired): run(['hdiutil','detach','-force',device],timeout=30)

def attach(image,mount,readonly=False):
    command=['hdiutil','attach','-nobrowse','-noautoopen','-mountpoint',mount,'-plist']
    if readonly: command.append('-readonly')
    info=plistlib.loads(run(command+[image]).encode())
    devices=[entry['dev-entry'] for entry in info['system-entities'] if 'dev-entry' in entry]
    return devices[0]

def finder_layout(mount,work,uninstaller=False):
    quoted=json.dumps(str(mount))
    background_file=json.dumps(str(mount/'.background/background.png'))
    uninstall_layout='set position of item "Uninstall Pocket Tank.app" to {500, 375}' if uninstaller else ''
    uninstall_readback=', position of item "Uninstall Pocket Tank.app"' if uninstaller else ''
    script=f'''tell application "Finder"
    set installerFolder to (POSIX file {quoted}) as alias
    open installerFolder
    delay 2
    set installerWindow to container window of installerFolder
    tell installerWindow
        set current view to icon view
        set toolbar visible to false
        set statusbar visible to false
        set bounds to {{160, 120, 800, 642}}
        tell «property icop» of installerWindow
            set «property iarr» to «constant earrnarr»
            set «property lvis» to 112
            set «property fsiz» to 13
            set «property ibkg» to (POSIX file {background_file}) as alias
        end tell
        set position of item "Pocket Tank.app" to {{160, 204}}
        set position of item "Applications" to {{480, 204}}
        set position of item "Read Me.txt" to {{75, 375}}
        {uninstall_layout}
        update installerFolder without registering applications
        delay 1
        {uninstall_layout}
        delay 1
        set actualLayout to {{current view, position of item "Pocket Tank.app", position of item "Applications", «property lvis» of («property icop» of installerWindow){uninstall_readback}}}
        close
    end tell
    return actualLayout
end tell
'''
    path=work/'finder-layout.applescript'; path.write_text(script)
    try:
        result=run(['osascript',path],timeout=25).strip()
        coordinates=[int(value) for value in re.findall(r'\d+',result)]
        if len(coordinates)!=(7 if uninstaller else 5) or not (120<=coordinates[0]<=210 and 440<=coordinates[2]<=530 and abs(coordinates[1]-204)<=10 and abs(coordinates[3]-204)<=10 and coordinates[4]==112):
            raise RuntimeError('Unexpected Finder layout response: '+result)
        if uninstaller and not (460<=coordinates[5]<=550 and abs(coordinates[6]-375)<=10):
            raise RuntimeError('Unexpected uninstaller Finder position: '+result)
        return 'Finder layout configured and positions verified: '+result
    except (subprocess.CalledProcessError,subprocess.TimeoutExpired,RuntimeError) as error:
        details=getattr(error,'stderr',None) or str(error)
        if isinstance(error, RuntimeError) or (isinstance(error, subprocess.CalledProcessError) and '-1743' not in details and '-1712' not in details):
            raise RuntimeError('Installer Finder layout failed: '+details.strip()) from error
        return 'Finder layout unavailable; functional app + Applications link + instructions retained. '+details.strip()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app',type=pathlib.Path,default=DEFAULT_APP)
    parser.add_argument('--uninstaller',type=pathlib.Path,help='Verified native Uninstall Pocket Tank.app to include (never executed).')
    parser.add_argument('--output',type=pathlib.Path,default=DEFAULT_OUTPUT)
    parser.add_argument('--work',type=pathlib.Path,default=ROOT/'work/mac-app/dmg-build')
    parser.add_argument('--report',type=pathlib.Path,default=ROOT/'work/mac-app/dmg-report.txt')
    args=parser.parse_args(); app=args.app.resolve(); output=args.output.resolve()
    if not app.is_dir() or app.suffix!='.app': raise SystemExit('App bundle does not exist: '+str(app))
    run(['codesign','--verify','--deep','--strict',app])
    with (app/'Contents/Info.plist').open('rb') as file: info=plistlib.load(file)
    if info.get('CFBundleIdentifier')!='com.local.pockettank': raise SystemExit('Unexpected aquarium bundle identifier')
    version=info.get('CFBundleShortVersionString','unknown')
    minimum=info['LSMinimumSystemVersion']
    architectures=run(['lipo','-archs',app/'Contents/MacOS/PocketTank']).strip().split()
    architecture_label=', '.join({'arm64':'Apple Silicon','x86_64':'Intel'}.get(a,a) for a in architectures)
    compatibility=f'This build declares macOS {minimum} or later and these architectures: {architecture_label}. Untested hardware/OS combinations are not verified.'
    uninstaller=args.uninstaller.resolve() if args.uninstaller else None
    if uninstaller:
        if not uninstaller.is_dir() or uninstaller.suffix!='.app': raise SystemExit('Uninstaller bundle does not exist: '+str(uninstaller))
        with (uninstaller/'Contents/Info.plist').open('rb') as file: uninstall_info=plistlib.load(file)
        if uninstall_info.get('CFBundleIdentifier')!='com.local.pockettank.uninstaller': raise SystemExit('Unexpected uninstaller bundle identifier')
        run(['codesign','--verify','--deep','--strict',uninstaller])
    args.work.mkdir(parents=True,exist_ok=True); output.parent.mkdir(parents=True,exist_ok=True)
    report=[]
    with tempfile.TemporaryDirectory(prefix='pocket-dmg-',dir=args.work) as temporary:
        work=pathlib.Path(temporary); stage=work/'stage'; stage.mkdir(); mount=work/'mount';mount.mkdir()
        run(['ditto',app,stage/'Pocket Tank.app'])
        if uninstaller: run(['ditto',uninstaller,stage/'Uninstall Pocket Tank.app'])
        (stage/'Applications').symlink_to('/Applications',target_is_directory=True)
        background=stage/'.background';background.mkdir()
        run(['swift',pathlib.Path(__file__).with_name('dmg_background.swift'),background/'background.png'])
        readme=f'''Pocket Tank for Mac\n\nINSTALL\nDrag Pocket Tank.app onto Applications in this window. Eject the Pocket Tank installer, then open Pocket Tank from Applications.\n\nPocket Tank runs its fish AI locally. It needs no account or internet connection. Click ⓘ for instructions and controls. Command-Q saves and quits.\n\nCOMPATIBILITY AND SHARING\n{compatibility}\n\nThe app has a local ad-hoc signature. It is not signed with an Apple Developer ID and has not been notarized by Apple. macOS may block a downloaded copy or ask you to approve it; this disk image does not bypass those security checks. Only open software from a source you trust.\n\nNo cloud service or publishing is included. You can share this DMG as a file. Original project: https://github.com/mediacutlet/pocket-tank (MIT license); license notices are bundled inside the app.\n'''
        if uninstaller:
            readme+='''
UNINSTALL
Keep this DMG so you can reopen it later. Double-click Uninstall Pocket Tank.app in this window. Review the confirmation before removing the installed app to Trash. The optional remove-data setting also removes the aquarium save and preferences; leave it off to keep your tank for a later reinstall. Cancel makes no changes. The uninstaller has not been run while creating this installer.
'''
        (stage/'Read Me.txt').write_text(readme)
        writable=work/'installer-rw.dmg'; compressed=work/'installer-final.dmg'
        run(['hdiutil','create','-ov','-srcfolder',stage,'-volname','Pocket Tank','-fs','HFS+','-format','UDRW',writable])
        device=attach(writable,mount)
        try:
            layout=finder_layout(mount,work,bool(uninstaller));report.append(layout)
            report.append('Finder .DS_Store exists: '+str((mount/'.DS_Store').exists()))
            run(['sync'])
        finally: detach(device)
        run(['hdiutil','convert',writable,'-format','UDZO','-imagekey','zlib-level=9','-o',compressed])
        report.append(run(['hdiutil','verify',compressed]).strip())
        image_info=plistlib.loads(run(['hdiutil','imageinfo','-plist',compressed]).encode())
        report.append('Disk image format: '+str(image_info.get('Format',image_info.get('format','UDZO'))))
        device=attach(compressed,mount,readonly=True)
        try:
            embedded=mount/'Pocket Tank.app'
            assert embedded.is_dir()
            assert (mount/'Applications').is_symlink() and os.readlink(mount/'Applications')=='/Applications'
            assert (mount/'Read Me.txt').is_file()
            run(['codesign','--verify','--deep','--strict',embedded])
            with (embedded/'Contents/Info.plist').open('rb') as file: embedded_info=plistlib.load(file)
            assert embedded_info['CFBundleShortVersionString']==version
            assert embedded_info.get('CFBundleIdentifier')=='com.local.pockettank'
            if uninstaller:
                embedded_uninstaller=mount/'Uninstall Pocket Tank.app'
                run(['codesign','--verify','--deep','--strict',embedded_uninstaller])
                with (embedded_uninstaller/'Contents/Info.plist').open('rb') as file: checked_uninstaller=plistlib.load(file)
                assert checked_uninstaller.get('CFBundleIdentifier')=='com.local.pockettank.uninstaller'
                report.append('Embedded native uninstaller identity and deep strict signature verified; uninstaller was never executed.')
            report.append('Read-only mount verified: app version '+version+', absolute /Applications symlink, Read Me, embedded deep strict code signature.')
        finally: detach(device)
        pending=output.with_name(output.name+'.tmp')
        shutil.copy2(compressed,pending);os.replace(pending,output)
    report.extend(['Output: '+str(output),'Bytes: '+str(output.stat().st_size),'Source version: '+version,'SHA-256: '+hashlib.sha256(output.read_bytes()).hexdigest(),'Invocation: python3 create_dmg.py --app APP [--uninstaller UNINSTALLER_APP] --output DMG --work WORKDIR --report REPORT','All installer mounts detached.',compatibility+' Ad-hoc signed, not Apple notarized.'])
    args.report.parent.mkdir(parents=True,exist_ok=True); args.report.write_text('\n'.join(report)+'\n')
    print('\n'.join(report))
if __name__=='__main__':main()
