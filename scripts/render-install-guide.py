#!/usr/bin/env python3
"""Render the README installation section as a self-contained offline HTML guide.

Uses only the Python standard library. Screenshots are embedded, so the HTML
continues to work after the DMG is ejected and can be copied as one file.
"""
import html
import base64
import plistlib
import re
import sys
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = 'https://github.com/benchiatc/cherry-keys-for-mac/blob/main/'


def inline(text):
    tokens = []

    def protect(fragment):
        tokens.append(fragment)
        return f'\x00{len(tokens) - 1}\x00'

    def code(match):
        return protect('<code>' + html.escape(match[1]) + '</code>')

    def link(match):
        image, label, target = match.groups()
        if image:
            resolved = (ROOT / target).resolve()
            if not resolved.is_relative_to(ROOT / 'docs/images/install') or not resolved.is_file():
                raise ValueError('Installation screenshot is missing or outside its directory.')
            data = resolved.read_bytes()
            if data[:8] != b'\x89PNG\r\n\x1a\n':
                raise ValueError('Installation screenshots must be PNG files.')
            width, height = struct.unpack('>II', data[16:24])
            url = 'data:image/png;base64,' + base64.b64encode(data).decode('ascii')
            image_id = 'image-' + resolved.stem
            thumbnail_id = 'thumb-' + resolved.stem
            image_tag = f'<img src="{url}" alt="{html.escape(label, quote=True)}" width="{width}" height="{height}" loading="lazy">'
            return protect(f'<a id="{thumbnail_id}" href="#{image_id}">{image_tag}</a><div class="lightbox" id="{image_id}"><a class="close-zoom" href="#{thumbnail_id}">Close screenshot ×</a>{image_tag}</div>')
        if not target.startswith(('https://', '#')):
            target = REPOSITORY + target
        return protect(f'<a href="{html.escape(target, quote=True)}">{html.escape(label)}</a>')

    text = re.sub(r'`([^`]+)`', code, text)
    text = re.sub(r'(!?)\[([^\]]+)\]\(([^)]+)\)', link, text)
    text = html.escape(text)
    text = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', text)
    for index, token in enumerate(tokens):
        text = text.replace(f'\x00{index}\x00', token)
    return text


def render(markdown):
    output, paragraph = [], []
    list_type = None
    table_open = False

    def flush():
        if paragraph:
            output.append('<p>' + inline(' '.join(paragraph)) + '</p>')
            paragraph.clear()

    def close_list():
        nonlocal list_type
        if list_type:
            output.append(f'</{list_type}>')
            list_type = None

    for line in markdown.splitlines() + ['']:
        stripped = line.strip()
        # README disclosure controls do not belong in the fully expanded offline guide.
        if stripped in {'<details>', '</details>'} or (
            stripped.startswith('<summary>') and stripped.endswith('</summary>')
        ):
            continue
        if not stripped:
            flush()
            close_list()
            if table_open:
                output.append('</tbody></table></div>')
                table_open = False
            continue
        if re.fullmatch(r'!\[[^\]]+\]\([^)]+\)', stripped):
            flush()
            close_list()
            output.append(inline(stripped))
            continue
        heading = re.match(r'^(#{3,4}) (.+)', stripped)
        if heading:
            flush()
            close_list()
            title = heading[2]
            anchor = re.sub(r'[^\w\s-]', '', title.lower()).replace(' ', '-')
            level = len(heading[1]) - 1
            output.append(f'<h{level} id="{anchor}">{inline(title)}</h{level}>')
            continue
        if stripped.startswith('|'):
            flush()
            close_list()
            cells = [c.strip() for c in stripped.strip('|').split('|')]
            if all(re.fullmatch(r'[:\- ]+', c) for c in cells):
                continue
            if not table_open:
                output.append('<div class="table-wrap"><table><thead><tr>' + ''.join('<th>' + inline(c) + '</th>' for c in cells) + '</tr></thead><tbody>')
                table_open = True
            else:
                output.append('<tr>' + ''.join('<td>' + inline(c) + '</td>' for c in cells) + '</tr>')
            continue
        item = re.match(r'^(\d+\.|-) (.+)', stripped)
        if item:
            flush()
            kind = 'ul' if item[1] == '-' else 'ol'
            if list_type != kind:
                close_list()
                output.append(f'<{kind}>')
                list_type = kind
            output.append('<li>' + inline(item[2]) + '</li>')
        else:
            close_list()
            paragraph.append(stripped)
    return '\n'.join(output)


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: render-install-guide.py <output.html>')
    readme = (ROOT / 'README.md').read_text()
    section = readme.split('### Option A: Install the DMG\n', 1)[1].split('### Option B: Build from source\n', 1)[0]
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    version = html.escape(info['CFBundleShortVersionString'])
    build = html.escape(info['CFBundleVersion'])
    content = render('### Option A: Install the DMG\n' + section)
    page = '''<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cherry Keys for Mac — Installation Guide</title>
<style>
*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#f4f3f0;color:#222;font:17px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}main{max-width:980px;margin:36px auto;padding:40px 48px;background:#fff;border-radius:20px}header{border-bottom:1px solid #ddd;margin-bottom:30px;padding-bottom:24px}.brand{font-size:13px;letter-spacing:2px;font-weight:750;color:#ba1736}h1{font-size:38px;line-height:1.15;letter-spacing:-1px}h2{margin-top:50px;font-size:27px}h3{margin-top:38px;font-size:22px;scroll-margin-top:20px}p{margin:18px 0}a{color:#b31634}nav{display:flex;flex-wrap:wrap;gap:10px}nav a{border:1px solid #ddd;border-radius:24px;padding:6px 13px;text-decoration:none;font-size:14px}li{padding:5px 0}code{font:0.9em ui-monospace,monospace;background:#f2f1ef;padding:2px 5px;border-radius:4px;overflow-wrap:anywhere}img{display:block;max-width:100%;height:auto;margin:24px auto;border:1px solid #ddd;border-radius:12px}.table-wrap{overflow:auto}table{border-collapse:collapse;width:100%;font-size:15px}th,td{text-align:left;border:1px solid #ddd;padding:13px;vertical-align:top}th{background:#f6f5f3}.lightbox{display:none}.lightbox:target{display:block;position:fixed;inset:0;z-index:100;background:rgba(20,20,24,.97);overflow:auto;padding:75px 24px 24px}.lightbox img{max-width:none;width:auto;margin:0 auto;border:0}.close-zoom{position:fixed;top:15px;right:24px;background:#fff;color:#222;border-radius:24px;padding:8px 18px;z-index:101;text-decoration:none}footer{border-top:1px solid #ddd;margin-top:36px;padding-top:16px;font-size:13px;color:#666}@media(max-width:680px){main{margin:0;padding:22px;border-radius:0}h1{font-size:30px}body{font-size:16px}}@media print{main{margin:0;padding:0}nav{display:none}h3{break-after:avoid}img{break-inside:avoid}}
</style><main><header><p class="brand">CHERRY KEYS FOR MAC</p><h1>Install and set up your keyboard</h1><p>Version VERSION · Build BUILD · Illustrated Mac setup guide</p><nav><a href="#2-open-the-dmg-and-copy-the-app">Copy the app</a><a href="#6-allow-accessibility">Permissions</a><a href="#9-set-up-and-approve-the-helper">Helper approval</a><a href="#11-confirm-that-setup-is-complete">Check it works</a></nav></header>
CONTENT
<footer>Independent community software. Not affiliated with CHERRY. This guide is generated from the README and can be read offline; external support and download links require the internet.</footer></main></html>'''.replace('VERSION', version).replace('BUILD', build).replace('CONTENT', content)
    destination = Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(page)
    print('Created illustrated offline installation guide.')


if __name__ == '__main__':
    main()
