#!/usr/bin/env python3
"""Collect guarded real-device Flutter timings; never treat idle gaps as FPS."""
import argparse
import json
import pathlib
import re
import subprocess
import time
import urllib.parse
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--uri', required=True, help='Profile VM service URL printed by flutter run --profile')
parser.add_argument('--device', required=True)
parser.add_argument('--scene', required=True)
parser.add_argument('--package', default='com.chhreader.chh_app')
parser.add_argument('--action', choices=['scroll', 'tabs'], default='scroll',
                    help='tabs alternates the warmed feed/forums destinations')
parser.add_argument('--output', default='/tmp/chh-performance')
args = parser.parse_args()
if not re.fullmatch(r'[A-Za-z0-9_-]+', args.scene):
    parser.error('scene must contain only letters, digits, - or _')
base = args.uri.rstrip('/') + '/'
adb = ['adb', '-s', args.device]

def run(*values):
    return subprocess.run(adb + list(values), check=True, capture_output=True, text=True).stdout

def rpc(name, **params):
    payload = json.load(urllib.request.urlopen(base + name + '?' + urllib.parse.urlencode(params)))
    if 'error' in payload:
        raise RuntimeError(payload['error'])
    return payload['result']

def current_isolate():
    return next(i['id'] for i in rpc('getVM')['isolates'] if not i.get('isSystemIsolate'))

def foreground():
    top = next((l for l in run('shell', 'dumpsys', 'activity', 'activities').splitlines()
                if 'topResumedActivity=' in l), '')
    if args.package + '/' not in top:
        raise RuntimeError('CHH left foreground; stopped without sending further input')
    if current_isolate() != isolate:
        raise RuntimeError('Flutter isolate restarted; this sample is invalid')

isolate = current_isolate()
foreground()
size = re.findall(r'(\d+)x(\d+)', run('shell', 'wm', 'size'))[-1]
width, height = map(int, size)
reset = rpc('ext.chh.frameMetrics', isolateId=isolate, action='reset')
if 'sampleCount' not in reset:
    raise RuntimeError('No valid frame recorder. Build in profile mode first.')
run('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-clear', '-enable')
output = pathlib.Path(args.output)
output.mkdir(parents=True, exist_ok=True)
try:
    displays = [rpc('ext.chh.frameMetrics', isolateId=isolate, action='display')]
    count = 30 if args.action == 'tabs' else 24
    for i in range(count):
        foreground()
        if args.action == 'tabs':
            x = str(round(width * (.375 if i % 2 == 0 else .125)))
            y = str(round(height * .934))
            run('shell', 'input', 'swipe', x, y, x, y, '80')
            time.sleep(.6)
        else:
            start, end = (.78, .26) if i < 12 else (.26, .78)
            run('shell', 'input', 'swipe', str(width // 2), str(round(height * start)),
                str(width // 2), str(round(height * end)), '450')
            time.sleep(.12)
        if i % 4 == 3:
            displays.append(rpc('ext.chh.frameMetrics', isolateId=isolate, action='display'))
    time.sleep(.25)
    foreground()
    result = rpc('ext.chh.frameMetrics', isolateId=isolate, action='read', includeFrames='true')
    if 'sampleCount' not in result:
        raise RuntimeError('Recorder response is stale or invalid')
    displays.append(result.get('display', {}))
    result.update(displaySamples=displays, package=args.package, scenario=args.scene, sampleValidity='foreground and isolate checked',
                  input=('30 alternating cached feed/forums tabs, 80ms press, 600ms gap'
                         if args.action == 'tabs' else
                         '24 swipes, 450ms each, twelve down and twelve up'),
                  screenPixels=[width, height])
    (output / (args.scene + '.json')).write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    (output / (args.scene + '-surface.txt')).write_text(
        run('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-dump'))
    print(json.dumps(result, ensure_ascii=False))
finally:
    run('shell', 'dumpsys', 'SurfaceFlinger', '--timestats', '-disable')
