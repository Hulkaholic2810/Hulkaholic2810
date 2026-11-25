#!/usr/bin/env python3
"""Package Pocket Lift Log into an unsigned APK without the Android SDK.

Writes the binary AndroidManifest.xml, a one-entry resources.arsc for the launcher icon, the icon itself,
the compiled classes.dex (built by build-apk.sh) and the web app as assets/index.html, with its Google
Fonts inlined so the app looks right offline.

usage: make_apk.py <workout-log.html> <classes.dex> <out.apk> <cache-dir>
"""
import base64
import io
import os
import re
import struct
import sys
import urllib.request
import zipfile

from PIL import Image, ImageDraw

PACKAGE = 'app.pocketlog'
LABEL = 'Pocket Log'
VERSION_CODE = 1
VERSION_NAME = '2.1-test'
MIN_SDK, TARGET_SDK = 21, 29
ICON_PATH = 'res/drawable-xxxhdpi-v4/icon.png'
ICON_ID = 0x7F010000
ANDROID_NS = 'http://schemas.android.com/apk/res/android'

# android.R.attr / android.R.style ids (read from the platform stub jar)
A = {
    'theme': 0x01010000, 'label': 0x01010001, 'icon': 0x01010002, 'name': 0x01010003,
    'exported': 0x01010010, 'screenOrientation': 0x0101001E, 'configChanges': 0x0101001F,
    'minSdkVersion': 0x0101020C, 'versionCode': 0x0101021B, 'versionName': 0x0101021C,
    'windowSoftInputMode': 0x0101022B, 'targetSdkVersion': 0x01010270, 'allowBackup': 0x01010280,
    'hardwareAccelerated': 0x010102D3,
}
THEME_NO_ACTION_BAR = 0x0103012C  # Theme.DeviceDefault.Light.NoActionBar


# ---------- binary XML / resource table chunks ----------
def string_pool(strings):
    offsets, data = [], b''
    for s in strings:
        offsets.append(len(data))
        u = s.encode('utf-16-le')
        data += struct.pack('<H', len(u) // 2) + u + b'\x00\x00'
    data += b'\x00' * (-len(data) % 4)
    start = 28 + 4 * len(strings)
    head = struct.pack('<HHIIIIII', 0x0001, 28, start + len(data), len(strings), 0, 0, start, 0)
    return head + b''.join(struct.pack('<I', o) for o in offsets) + data


def manifest_xml():
    # element: (tag, [(attr, kind, value)], [children]); attrs with an android id use the android namespace
    activity = ('activity', [
        ('name', 'str', PACKAGE + '.MainActivity'), ('exported', 'bool', True),
        ('screenOrientation', 'int', 1),          # portrait
        ('configChanges', 'hex', 0x04A0),         # orientation | keyboardHidden | screenSize
        ('windowSoftInputMode', 'hex', 0x10),     # adjustResize
    ], [('intent-filter', [], [
        ('action', [('name', 'str', 'android.intent.action.MAIN')], []),
        ('category', [('name', 'str', 'android.intent.category.LAUNCHER')], []),
    ])])
    root = ('manifest', [
        ('package', 'str', PACKAGE), ('versionCode', 'int', VERSION_CODE), ('versionName', 'str', VERSION_NAME),
    ], [
        ('uses-sdk', [('minSdkVersion', 'int', MIN_SDK), ('targetSdkVersion', 'int', TARGET_SDK)], []),
        ('uses-permission', [('name', 'str', 'android.permission.INTERNET')], []),
        ('uses-permission', [('name', 'str', 'android.permission.VIBRATE')], []),
        ('application', [
            ('label', 'str', LABEL), ('icon', 'ref', ICON_ID), ('theme', 'ref', THEME_NO_ACTION_BAR),
            ('allowBackup', 'bool', True), ('hardwareAccelerated', 'bool', True),
        ], [activity]),
    ])

    # string pool: android attribute names first (in id order, matching the resource map), then everything else
    used_attrs, others = set(), []

    def walk(el):
        tag, attrs, kids = el
        others.append(tag)
        for name, kind, value in attrs:
            if name in A:
                used_attrs.add(name)
            else:
                others.append(name)
            if kind == 'str':
                others.append(value)
        for k in kids:
            walk(k)
    walk(root)
    attr_names = sorted(used_attrs, key=lambda n: A[n])
    strings = list(attr_names)
    for s in ['android', ANDROID_NS] + others:
        if s not in strings:
            strings.append(s)
    idx = {s: i for i, s in enumerate(strings)}

    body = b''
    res_map = struct.pack('<HHI', 0x0180, 8, 8 + 4 * len(attr_names)) + b''.join(struct.pack('<I', A[n]) for n in attr_names)
    line = [1]

    def emit(el):
        nonlocal body
        tag, attrs, kids = el
        ln = line[0]; line[0] += 1
        enc = []
        for name, kind, value in sorted(attrs, key=lambda a: A.get(a[0], -1)):
            ns = idx[ANDROID_NS] if name in A else -1
            raw = -1
            if kind == 'str':
                raw = idx[value]; dtype, data = 0x03, idx[value]
            elif kind == 'int':
                dtype, data = 0x10, value
            elif kind == 'hex':
                dtype, data = 0x11, value
            elif kind == 'bool':
                dtype, data = 0x12, 0xFFFFFFFF if value else 0
            else:  # ref
                dtype, data = 0x01, value
            enc.append(struct.pack('<iiiHBBI', ns, idx[name], raw, 8, 0, dtype, data))
        attr_bytes = b''.join(enc)
        body += struct.pack('<HHIIi', 0x0102, 16, 36 + len(attr_bytes), ln, -1)
        body += struct.pack('<iIHHHHHH', -1, idx[tag], 20, 20, len(enc), 0, 0, 0) + attr_bytes
        for k in kids:
            emit(k)
        body += struct.pack('<HHIIiiI', 0x0103, 16, 24, ln, -1, -1, idx[tag])

    ns_start = struct.pack('<HHIIiII', 0x0100, 16, 24, 1, -1, idx['android'], idx[ANDROID_NS])
    emit(root)
    ns_end = struct.pack('<HHIIiII', 0x0101, 16, 24, line[0], -1, idx['android'], idx[ANDROID_NS])
    content = string_pool(strings) + res_map + ns_start + body + ns_end
    return struct.pack('<HHI', 0x0003, 8, 8 + len(content)) + content


def resources_arsc():
    values = string_pool([ICON_PATH])
    types, keys = string_pool(['drawable']), string_pool(['icon'])
    spec = struct.pack('<HHIBBHI', 0x0202, 16, 20, 1, 0, 0, 1) + struct.pack('<I', 0x0100)  # varies by density
    config = bytearray(64)
    struct.pack_into('<I', config, 0, 64)
    struct.pack_into('<H', config, 14, 640)   # xxxhdpi
    struct.pack_into('<H', config, 24, 4)     # -v4, as aapt writes density qualifiers
    entry = struct.pack('<HHI', 8, 0, 0) + struct.pack('<HBBI', 8, 0, 0x03, 0)  # key "icon" -> values[0]
    typ = struct.pack('<HHIBBHII', 0x0201, 84, 88 + len(entry), 1, 0, 0, 1, 88) + bytes(config) + struct.pack('<I', 0) + entry
    name = PACKAGE.encode('utf-16-le').ljust(256, b'\x00')
    pkg_body = types + keys + spec + typ
    pkg = struct.pack('<HHII', 0x0200, 288, 288 + len(pkg_body), 0x7F) + name
    pkg += struct.pack('<IIIII', 288, 0, 288 + len(types), 0, 0) + pkg_body
    return struct.pack('<HHII', 0x0002, 12, 12 + len(values) + len(pkg), 1) + values + pkg


# ---------- icon: an inked check box on warm paper ----------
def icon_png():
    S = 768
    im = Image.new('RGB', (S, S), (0xF9, 0xF8, 0xF6))
    d = ImageDraw.Draw(im)
    box = 340
    x0 = y0 = (S - box) // 2
    d.rounded_rectangle([x0, y0, x0 + box, y0 + box], radius=48, fill=(0x1A, 0x1A, 0x1A))
    pts = [(x0 + box * .25, y0 + box * .53), (x0 + box * .43, y0 + box * .70), (x0 + box * .76, y0 + box * .33)]
    d.line(pts, fill=(0xF9, 0xF8, 0xF6), width=40, joint='curve')
    for p in (pts[0], pts[2]):
        d.ellipse([p[0] - 20, p[1] - 20, p[0] + 20, p[1] + 20], fill=(0xF9, 0xF8, 0xF6))
    out = io.BytesIO()
    im.resize((192, 192), Image.LANCZOS).save(out, 'PNG', optimize=True)
    return out.getvalue()


# ---------- web app with fonts inlined ----------
def inline_fonts(html, cache):
    m = re.search(r'<link rel="stylesheet" href="(https://fonts\.googleapis\.com/css2\?[^"]+)">', html)
    if not m:
        return html
    try:
        ua = {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36'}
        css = urllib.request.urlopen(urllib.request.Request(m.group(1).replace('&amp;', '&'), headers=ua), timeout=30).read().decode()
        blocks = re.findall(r'/\* ([\w-]+) \*/\s*(@font-face\s*{[^}]+})', css)
        keep = []
        for subset, block in blocks:
            if subset not in ('latin', 'latin-ext'):
                continue
            url = re.search(r'url\((https://[^)]+)\)', block).group(1)
            path = os.path.join(cache, re.sub(r'[^\w.]', '_', url.split('/s/')[-1]))
            if not os.path.exists(path):
                with open(path, 'wb') as f:
                    f.write(urllib.request.urlopen(url, timeout=30).read())
            data = base64.b64encode(open(path, 'rb').read()).decode()
            keep.append(block.replace(url, 'data:font/woff2;base64,' + data))
        if not keep:
            return html
        html = re.sub(r'<link rel="preconnect"[^>]*>\n', '', html)
        return html.replace(m.group(0), '<style>\n' + '\n'.join(keep) + '\n</style>')
    except Exception as e:  # offline build: keep the online fonts, the page falls back to system faces
        print('fonts not inlined:', e, file=sys.stderr)
        return html


def write_aligned(z, name, data, align=4):
    info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    offset = z.fp.tell() + 30 + len(name.encode())
    info.extra = b'\x00' * (-offset % align)
    z.writestr(info, data)


def main():
    html_path, dex_path, out_path, cache = sys.argv[1:5]
    os.makedirs(cache, exist_ok=True)
    html = inline_fonts(open(html_path, encoding='utf-8').read(), cache)
    with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr(zipfile.ZipInfo('AndroidManifest.xml', (2026, 1, 1, 0, 0, 0)), manifest_xml(), zipfile.ZIP_DEFLATED)
        z.writestr(zipfile.ZipInfo('classes.dex', (2026, 1, 1, 0, 0, 0)), open(dex_path, 'rb').read(), zipfile.ZIP_DEFLATED)
        write_aligned(z, 'resources.arsc', resources_arsc())
        write_aligned(z, ICON_PATH, icon_png())
        z.writestr(zipfile.ZipInfo('assets/index.html', (2026, 1, 1, 0, 0, 0)), html.encode('utf-8'), zipfile.ZIP_DEFLATED)
    print('packaged', out_path, os.path.getsize(out_path), 'bytes; html', len(html), 'chars')


if __name__ == '__main__':
    main()
