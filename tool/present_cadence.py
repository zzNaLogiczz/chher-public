#!/usr/bin/env python3
"""Read the app layer's own present timestamps while a sample runs.

SurfaceFlinger's global timestats mix every window and idle time, so they
cannot show whether CHH itself was presented at 120Hz (QA08). This polls
`dumpsys SurfaceFlinger --latency <layer>` for the Flutter SurfaceView of the
package (the dump only keeps ~128 frames, about one second), merges the polls
and classifies each interval between actual presents against a fixed 120Hz
vsync. Gaps of 50ms or more are idle time, not drops.

Run it in parallel with tool/profile_scroll.py or an interaction script:
  python3 tool/present_cadence.py --device DEVICE_ID \
    --package com.chhreader.chh_app.preview --seconds 30 \
    --output build/qa/ui-redesign/performance/<scene>-present.json
"""
import argparse
import json
import pathlib
import subprocess
import time

VSYNC_120_NS = 1e9 / 120
IDLE_NS = 50_000_000
PENDING = 9_223_372_036_854_775_807


def parse_latency(text):
    """Return (refresh period ns, actual present timestamps ns)."""
    lines = [line.split() for line in text.strip().splitlines() if line.strip()]
    if not lines:
        raise ValueError('empty --latency dump: wrong layer name or no frames')
    period = int(lines[0][0])
    presents = []
    for row in lines[1:]:
        if len(row) < 3:
            continue
        actual = int(row[1])
        if 0 < actual < PENDING:
            presents.append(actual)
    return period, presents


def merge(polls):
    return sorted({stamp for poll in polls for stamp in poll})


def pick_layer(layer_list, package):
    """The Flutter content layer is the BLAST SurfaceView of the package."""
    matches = [
        line.strip() for line in layer_list.splitlines()
        if line.strip().startswith('SurfaceView[' + package + '/')
    ]
    if not matches:
        raise ValueError('no SurfaceView layer for ' + package)
    return matches[-1]


def cadence(presents):
    at120 = at60 = longer = idle = 0
    for a, b in zip(presents, presents[1:]):
        gap = b - a
        if gap >= IDLE_NS:
            idle += 1
        elif gap < 1.5 * VSYNC_120_NS:
            at120 += 1
        elif gap < 2.5 * VSYNC_120_NS:
            at60 += 1
        else:
            longer += 1
    active = at120 + at60 + longer
    return dict(
        presentedFrames=len(presents),
        activeIntervals=active,
        idleGaps=idle,
        at120=at120,
        at60=at60,
        longer=longer,
        at120Share=round(at120 / active, 4) if active else None,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--package', default='com.chhreader.chh_app.preview')
    parser.add_argument('--seconds', type=float, default=30)
    parser.add_argument('--interval', type=float, default=.4)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    def adb(*values):
        return subprocess.run(['adb', '-s', args.device, 'shell', *values],
                              check=True, capture_output=True, text=True).stdout

    layer = pick_layer(adb('dumpsys', 'SurfaceFlinger', '--list'), args.package)
    quoted = "'" + layer + "'"
    adb('dumpsys', 'SurfaceFlinger', '--latency-clear', quoted)
    polls, periods = [], set()
    deadline = time.monotonic() + args.seconds
    while time.monotonic() < deadline:
        period, presents = parse_latency(
            adb('dumpsys', 'SurfaceFlinger', '--latency', quoted))
        periods.add(period)
        polls.append(presents)
        time.sleep(args.interval)
    presents = merge(polls)
    result = dict(layer=layer, refreshPeriodsNs=sorted(periods),
                  polls=len(polls), **cadence(presents), presentsNs=presents)
    out = pathlib.Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'presentsNs'}))


if __name__ == '__main__':
    main()
