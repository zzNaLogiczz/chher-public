import unittest
from check_performance import evaluate


class AcceptanceTests(unittest.TestCase):
    def sample(self):
        return dict(buildMode='profile', sampleCount=1000, sampleSpanMs=12000,
                    evictedSampleCount=0, budgetHz=120,
                    displaySamples=[dict(foreground=True, actualRefreshRate=120)] * 3,
                    ui=dict(p95Ms=4, p99Ms=8, maxMs=12),
                    raster=dict(p95Ms=3, p99Ms=6, maxMs=10),
                    buildOrRasterOverBudgetCount=10, maxConsecutiveOverTwoBudgets=0)

    def test_stage_pass_never_claims_presentation_or_response_pass(self):
        result = evaluate(self.sample())
        self.assertEqual(result['flutterFrameStatus'], 'pass')
        self.assertEqual(result['overallStatus'], 'not-accepted')

    def test_stalls_fail_despite_good_averages(self):
        sample = self.sample()
        sample['buildOrRasterOverBudgetCount'] = 11
        sample['maxConsecutiveOverTwoBudgets'] = 3
        self.assertEqual(evaluate(sample)['flutterFrameStatus'], 'fail')

    def test_debug_missing_evicted_or_downclocked_sample_is_invalid(self):
        for key, value in [('buildMode', 'debug'), ('sampleCount', 0),
                           ('sampleSpanMs', 9999), ('evictedSampleCount', 1),
                           ('displaySamples', [dict(actualRefreshRate=60)] * 3),
                           ('ui', dict(p95Ms=float('nan')))]:
            sample = self.sample()
            sample[key] = value
            self.assertEqual(evaluate(sample)['flutterFrameStatus'], 'invalid')


if __name__ == '__main__':
    unittest.main()
