#!/bin/bash
# Local certificate-signed builds; no notarization or installation.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$PWD/local-build"
mkdir -p "$OUT"
BC_SIGN_IDENTITY="$(python3 contributions/scripts/select_local_signing_identity.py)"
swiftc -O -target x86_64-apple-macosx10.15 -sdk "$(xcrun --sdk macosx --show-sdk-path)" LegacyMacReceiver/Sources/LegacyMacReceiver/*.swift -o "$OUT/LegacyMacReceiver"
swift build -c release --product BetterCastSender
BIN_DIR="$(swift build -c release --show-bin-path)"
python3 - "$OUT" "$BIN_DIR" "$BC_SIGN_IDENTITY" <<'PY'
import pathlib, shutil, sys, subprocess, plistlib
out, binaries = map(pathlib.Path, sys.argv[1:3])
identity = sys.argv[3]
for name, binary, plist in [
    ('BetterCast Receiver', out/'LegacyMacReceiver', pathlib.Path('LegacyMacReceiver/Info.plist')),
    ('BetterCast', binaries/'BetterCastSender', pathlib.Path('BetterCastSender-Info.plist')),
]:
    app=out/(name+'.app')
    if app.exists(): shutil.rmtree(app)
    contents=app/'Contents'
    (contents/'MacOS').mkdir(parents=True)
    (contents/'Resources').mkdir()
    shutil.copy2(binary, contents/'MacOS'/binary.name)
    info=plistlib.loads(plist.read_bytes())
    info['CFBundleDisplayName']=name
    # Keep custom builds from replacing themselves with upstream releases.
    info['SUEnableAutomaticChecks']=False
    info.pop('SUFeedURL', None)
    (contents/'Info.plist').write_bytes(plistlib.dumps(info))
    shutil.copy2('assets/branding/BetterCastIcon.icns', contents/'Resources/AppIcon.icns')
    for locale in pathlib.Path('localization').glob('*.lproj'):
        shutil.copytree(locale, contents/'Resources'/locale.name)
    if binary.name=='BetterCastSender':
        (contents/'Frameworks').mkdir()
        shutil.copytree(binaries/'Sparkle.framework', contents/'Frameworks/Sparkle.framework', symlinks=True)
        subprocess.run(['install_name_tool','-add_rpath','@executable_path/../Frameworks',str(contents/'MacOS'/binary.name)],check=True)
    def sign(target, preserve_entitlements=False):
        args = ['codesign', '--force', '--sign', identity]
        if preserve_entitlements:
            args.append('--preserve-metadata=entitlements')
        subprocess.run(args + [str(target)], check=True)
    if binary.name == 'BetterCastSender':
        framework = contents/'Frameworks/Sparkle.framework'
        sparkle = framework/'Versions/B'
        sign(sparkle/'XPCServices/Installer.xpc')
        sign(sparkle/'XPCServices/Downloader.xpc', preserve_entitlements=True)
        sign(sparkle/'Autoupdate')
        sign(sparkle/'Updater.app')
        sign(framework)
    sign(app)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    print(app)
PY
