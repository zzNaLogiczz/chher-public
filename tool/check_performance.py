#!/usr/bin/env python3
"""Check one 120Hz Flutter sample. Presentation/response require separate evidence."""
import argparse
import json
import math
from pathlib import Path


def evaluate(sample):
    invalid, failures = [], []
    if sample.get('buildMode') not in ('profile', 'release'):
        invalid.append('profile/release build required')
    count = sample.get('sampleCount', 0)
    if not isinstance(count, int) or count < 600:
        invalid.append('at least 600 frames required')
    if sample.get('sampleSpanMs', 0) < 10000:
        invalid.append('at least 10 seconds required')
    if sample.get('evictedSampleCount', 1) != 0:
        invalid.append('samples missing or evicted')
    if sample.get('budgetHz') != 120:
        invalid.append('120Hz budget required')
    displays = sample.get('displaySamples', [])
    if len(displays) < 3 or any(not d.get('foreground') or
        not 119 <= (d.get('actualRefreshRate') or 0) <= 121 for d in displays):
        invalid.append('foreground 120Hz samples required at start, during and end')
    for stage in ('ui', 'raster'):
        for key, limit in [('p95Ms', 1000 / 120), ('p99Ms', 1000 / 60), ('maxMs', 50)]:
            value = sample.get(stage, {}).get(key)
            if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                invalid.append(f'{stage}.{key} missing or invalid')
            elif value > limit:
                failures.append(f'{stage}.{key} {value:.3f} > {limit:.3f}ms')
    over = sample.get('buildOrRasterOverBudgetCount')
    if not isinstance(over, int) or not isinstance(count, int) or not 0 <= over <= count:
        invalid.append('over-budget count missing or invalid')
    elif count and over / count > .01:
        failures.append(f'over-budget ratio {over / count:.2%} > 1%')
    streak = sample.get('maxConsecutiveOverTwoBudgets')
    if not isinstance(streak, int) or streak < 0:
        invalid.append('consecutive stalls missing')
    elif streak > 2:
        failures.append(f'{streak} consecutive frames exceed two budgets')
    return {'flutterFrameStatus': 'invalid' if invalid else 'fail' if failures else 'pass',
            'invalidReasons': invalid, 'failures': failures,
            'presentationStatus': 'not-measured', 'responseStatus': 'not-measured',
            'overallStatus': 'not-accepted'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sample', type=Path)
    args = parser.parse_args()
    result = evaluate(json.loads(args.sample.read_text()))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    # This command only gates Flutter timings, not whole-app acceptance.
    raise SystemExit(0 if result['flutterFrameStatus'] == 'pass' else 1)
