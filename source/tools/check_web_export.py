#!/usr/bin/env python3
"""Local-only Chromium smoke check for an existing Godot Web export; never edits the project."""
import argparse
import functools
import hashlib
import http.server
import json
import re
import tempfile
import threading
import time
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
project = Path(__file__).resolve().parents[1]
parser.add_argument('--root', type=Path, default=project / 'builds/web')
parser.add_argument('--artifacts', type=Path, default=project / 'builds/web-validation')
args = parser.parse_args()
root = Path(args.root).resolve()
artifacts = Path(args.artifacts).resolve()
if not (root / 'index.html').is_file():
    raise SystemExit('Export missing: index.html. No browser or server started.')
artifacts.mkdir(parents=True, exist_ok=True)
initial_pck_sha256 = hashlib.file_digest((root / 'index.pck').open('rb'), 'sha256').hexdigest()
report = {'artifact_sha256': {'index.pck': initial_pck_sha256}, 'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'root': str(root), 'console': [], 'page_errors': [], 'request_failures': [], 'http_errors': [], 'external_requests_blocked': [], 'checks': {}, 'screenshots': [], 'limitation': 'Single Linux Chromium / software WebGL smoke check. Does not establish full browser, audio, performance, save, or full-run compatibility.'}

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm', '.pck': 'application/octet-stream'}
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()
    def log_message(self, fmt, *values):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(root)))
server_thread = threading.Thread(target=server.serve_forever, daemon=True)
server_thread.start()
url = f'http://127.0.0.1:{server.server_port}/index.html'
print('Local server started; launching Chromium', flush=True)
try:
    with tempfile.TemporaryDirectory(prefix='wf2-chromium-') as profile:
        with sync_playwright() as p:
            context = p.chromium.launch_persistent_context(profile, executable_path='/usr/bin/chromium', headless=True, viewport={'width':1280,'height':800}, device_scale_factor=1, args=['--no-sandbox','--disable-dev-shm-usage','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--no-proxy-server'], timeout=30000)
            context.route('**/*', lambda route: route.continue_() if urlsplit(route.request.url).hostname in ('127.0.0.1', 'localhost', None) else (report['external_requests_blocked'].append(route.request.url), route.abort())[-1])
            page = context.pages[0] if context.pages else context.new_page()
            page.on('console', lambda msg: report['console'].append({'type': msg.type, 'text': msg.text}))
            page.on('pageerror', lambda error: report['page_errors'].append(str(error)))
            page.on('requestfailed', lambda request: report['request_failures'].append({'url':request.url,'failure':request.failure}))
            page.on('response', lambda response: report['http_errors'].append({'url':response.url,'status':response.status}) if response.status >= 400 else None)
            response = page.goto(url, wait_until='domcontentloaded', timeout=30000)
            report['checks']['html_http_status'] = response.status
            report['checks']['title'] = page.title()
            page.wait_for_function("() => { const c=document.querySelector('canvas');const s=document.querySelector('#status');return c && c.width>0 && c.height>0 && (!s || getComputedStyle(s).display === 'none' || getComputedStyle(s).visibility === 'hidden'); }", timeout=90000)
            page.wait_for_timeout(3500)
            def screenshot(name):
                path = artifacts / (name+'.png')
                page.screenshot(path=str(path), full_page=False)
                report['screenshots'].append(str(path))
                print('Captured '+name, flush=True)
            screenshot('web-base')
            report['checks']['canvas'] = page.locator('canvas').first.evaluate('(c)=>({width:c.width,height:c.height,rect:{width:c.getBoundingClientRect().width,height:c.getBoundingClientRect().height}})')
            report['checks']['cross_origin_isolated'] = page.evaluate('crossOriginIsolated')
            report['checks']['godot_started'] = any('Godot Engine' in msg['text'] for msg in report['console'])
            page.mouse.click(1090, 429)
            page.wait_for_timeout(3000)
            screenshot('web-training')
            page.keyboard.press('2')
            page.wait_for_timeout(2000)
            screenshot('web-training-blue')
            page.keyboard.press('3')
            page.wait_for_timeout(2000)
            screenshot('web-training-gold')
            page.keyboard.press('Escape')
            page.wait_for_timeout(500)
            screenshot('web-pause')
            page.keyboard.press('Escape')
            page.wait_for_timeout(500)
            screenshot('web-resumed')
            report['checks']['input_sequence_sent'] = ['click training at 1090,429', '2', '3', 'Escape', 'Escape']
            report['checks']['engine_or_script_errors'] = [msg for msg in report['console'] if re.search(r'(^|\s)(SCRIPT ERROR|ERROR):|Parse Error|Failed to load script', msg['text'])]
            report['checks']['browser_console_errors'] = [msg for msg in report['console'] if msg['type']=='error']
            report['checks']['visual_review_required'] = True
            context.close()
            assert report['checks']['html_http_status'] == 200
            assert report['checks']['godot_started']
            assert not report['checks']['engine_or_script_errors']
            assert not report['checks']['browser_console_errors']
            assert not report['page_errors']
            assert not report['request_failures']
            assert not report['http_errors']
            assert hashlib.file_digest((root / 'index.pck').open('rb'), 'sha256').hexdigest() == initial_pck_sha256, 'Export changed during the browser check'
except Exception as exc:
    report['exception'] = repr(exc)
    raise
finally:
    server.shutdown()
    server.server_close()
    report['checks']['pck_unchanged_during_run'] = hashlib.file_digest((root / 'index.pck').open('rb'), 'sha256').hexdigest() == initial_pck_sha256
    report['completed_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    (artifacts/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'report':str(artifacts/'report.json'),'checks':report['checks'],'page_errors':report['page_errors'],'http_errors':report['http_errors'],'request_failures':report['request_failures'],'exception':report.get('exception')}, ensure_ascii=False), flush=True)
