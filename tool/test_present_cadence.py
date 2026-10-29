import unittest
from present_cadence import cadence, merge, parse_latency, pick_layer

PERIOD = 8_333_333
PENDING = 9_223_372_036_854_775_807


def dump(presents):
    lines = [str(PERIOD)]
    lines += [f'{p - 1_000_000}\t{p}\t{p - 500_000}' for p in presents]
    lines.append(f'0\t{PENDING}\t0')
    return '\n'.join(lines) + '\n'


class ParseTests(unittest.TestCase):
    def test_reads_period_and_actual_present_skipping_pending_rows(self):
        period, presents = parse_latency(dump([100, 200]))
        self.assertEqual(period, PERIOD)
        self.assertEqual(presents, [100, 200])

    def test_empty_dump_is_an_error_not_a_pass(self):
        with self.assertRaises(ValueError):
            parse_latency('')

    def test_overlapping_polls_merge_without_duplicates(self):
        self.assertEqual(merge([[1, 2, 3], [2, 3, 4]]), [1, 2, 3, 4])

    def test_picks_the_flutter_surface_of_the_package(self):
        layers = '\n'.join([
            'StatusBar#12',
            'com.example/com.example.Main#40',
            'SurfaceView[com.example/com.example.Main](BLAST)#41',
            'Background for SurfaceView[com.example/com.example.Main]#42',
        ])
        self.assertEqual(
            pick_layer(layers, 'com.example'),
            'SurfaceView[com.example/com.example.Main](BLAST)#41',
        )

    def test_missing_layer_is_an_error(self):
        with self.assertRaises(ValueError):
            pick_layer('StatusBar#12', 'com.example')


class CadenceTests(unittest.TestCase):
    def test_steady_120hz_counts_every_interval_as_one_vsync(self):
        presents = [i * PERIOD for i in range(200)]
        result = cadence(presents)
        self.assertEqual(result['activeIntervals'], 199)
        self.assertEqual(result['at120'], 199)
        self.assertEqual(result['at120Share'], 1.0)

    def test_idle_gaps_are_excluded_not_counted_as_drops(self):
        first = [i * PERIOD for i in range(60)]
        second = [first[-1] + 2_000_000_000 + i * PERIOD for i in range(60)]
        result = cadence(first + second)
        self.assertEqual(result['activeIntervals'], 118)
        self.assertEqual(result['idleGaps'], 1)
        self.assertEqual(result['at120'], 118)

    def test_60hz_and_missed_frames_are_reported_separately(self):
        presents = [0, PERIOD, 3 * PERIOD, 5 * PERIOD, 8 * PERIOD]
        result = cadence(presents)
        self.assertEqual(result['at120'], 1)
        self.assertEqual(result['at60'], 2)
        self.assertEqual(result['longer'], 1)


if __name__ == '__main__':
    unittest.main()
