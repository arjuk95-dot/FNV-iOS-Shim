"""Compile the owner-approved game icon with Apple's iOS asset compiler."""
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess

SOURCE=Path(__file__).resolve().parents[1]/'ios/Assets/AppIcon.png'

def compile_icon(work,app):
    work,app=Path(work),Path(app)
    data=SOURCE.read_bytes()
    assert data[:8]==b'\x89PNG\r\n\x1a\n'
    width,height=struct.unpack_from('>II',data,16)
    assert width==height and 1024<=width<=8192 and data[25]==2,'Expected an opaque RGB square icon'
    catalog=work/'Assets.xcassets'
    icons=catalog/'AppIcon.appiconset'
    icons.mkdir(parents=True)
    (catalog/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
    (icons/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon1024.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}}))
    subprocess.run(['sips','--resampleHeightWidth','1024','1024',str(SOURCE),'--out',str(icons/'AppIcon1024.png')],check=True)
    partial=work/'app-icon-info.plist'
    subprocess.run(['xcrun','actool',str(catalog),'--compile',str(app),'--platform','iphoneos',
                    '--minimum-deployment-target','18.0','--app-icon','AppIcon','--target-device','iphone',
                    '--target-device','ipad','--output-partial-info-plist',str(partial),
                    '--warnings','--notices','--output-format','human-readable-text'],check=True)
    info=plistlib.loads(partial.read_bytes())
    assert info['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName']=='AppIcon'
    assert (app/'Assets.car').is_file() and (app/'Assets.car').stat().st_size>0
    # Modern actool keeps some sizes in Assets.car. Supply loose high-density
    # renditions too, for guest-container icon readers that inspect PNG files.
    for pixels,name in [(120,'AppIcon60x60@2x.png'),(180,'AppIcon60x60@3x.png'),(152,'AppIcon76x76@2x~ipad.png'),(167,'AppIcon83.5x83.5@2x~ipad.png')]:
        if not (app/name).exists():
            subprocess.run(['sips','--resampleHeightWidth',str(pixels),str(pixels),str(icons/'AppIcon1024.png'),'--out',str(app/name)],check=True)
    ipad=info['CFBundleIcons~ipad']['CFBundlePrimaryIcon']['CFBundleIconFiles']
    if 'AppIcon83.5x83.5' not in ipad:ipad.append('AppIcon83.5x83.5')
    shutil.copyfile(icons/'AppIcon1024.png',app/'AppIcon.png')
    info['CFBundleIconFile']='AppIcon.png'
    return {key:value for key,value in info.items() if key in ['CFBundleIcons','CFBundleIcons~ipad','CFBundleIconFile']}
