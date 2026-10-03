"""Keep unavailable presentation feedback distinct from GPU failure or lateness."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('probe', Path(__file__).resolve().parents[2] /
                                            'scripts/macos/analyze-cadence-probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


def row(**changes):
    result = dict(gpu_status=4, gpu_start_s=1.002, gpu_end_s=1.003,
                  callback=1, presented_media_s=1.025, presented_callback_s=1.026,
                  active=1, visible=1, ready_s=1, submit_media_s=1.001,
                  deadline_s=1.010, expected_s=1.020, present_requested_s=1.004)
    result.update(changes)
    return {k: str(v) for k, v in result.items()}


class ProbeTests(unittest.TestCase):
    def test_zero_presentation_does_not_mean_gpu_failure(self):
        result = probe.stages([row(presented_media_s=0)])
        self.assertEqual(result['gpu_completed'], 1)
        self.assertEqual(result['gpu_errors'], 0)
        self.assertEqual(result['presentation_callback_with_zero_time'], 1)
        self.assertIsNone(result['presented_minus_expected_ms'])

    def test_pending_and_error_do_not_create_gpu_durations(self):
        result = probe.stages([row(gpu_status=0, callback=0, gpu_start_s=0, gpu_end_s=0,
                                  presented_media_s=0), row(gpu_status=5)])
        self.assertEqual(result['gpu_pending'], 1)
        self.assertEqual(result['gpu_errors'], 1)
        self.assertEqual(result['presentation_callback_pending'], 1)
        self.assertIsNone(result['gpu_execution_ms'])

    def test_cpu_deadline_and_gpu_expected_time_are_distinct(self):
        result = probe.stages([row(gpu_end_s=1.015), row(gpu_end_s=1.021)])
        self.assertEqual(result['cpu_submit_after_deadline'], 0)
        self.assertEqual(result['gpu_end_after_expected_presentation'], 1)
        self.assertEqual(result['presented_minus_expected_ms']['mean'], 5)

    def test_present_request_can_miss_deadline_after_timely_commit(self):
        result = probe.stages([row(present_requested_s=1.011)])
        self.assertEqual(result['cpu_submit_after_deadline'], 0)
        self.assertEqual(result['present_request_after_deadline'], 1)


if __name__ == '__main__':
    unittest.main()
