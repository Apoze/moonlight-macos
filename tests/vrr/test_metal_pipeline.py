"""Regression checks for the diagnostic joins, denominators and clock boundaries."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('pipeline', Path(__file__).parents[2] /
                                           'scripts/macos/analyze-pipeline.py')
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)


def worker(sequence, arrival, presented=True, frame=None):
    return dict(arrival_sequence=str(sequence), frame=str(sequence if frame is None else frame),
                pacer_arrival_us=str(arrival), presented=str(int(presented)),
                disposition='presented' if presented else 'queue_stale',
                frame_receive_us=str(arrival-300), frame_reassembled_us=str(arrival-200),
                decode_submit_us=str(arrival-150), decoder_output_us=str(arrival-10),
                dequeue_us=str(arrival+20), prepare_end_us=str(arrival+100),
                submission_boundary_us=str(arrival+150), prepare_timing_valid='1',
                prepare_acquire_us='30', prepare_render_us='50', prepare_us='80',
                playout_delay_us='100', submission_id=str(sequence),
                submission_id_valid=str(int(presented)), rtp_timestamp=str(sequence*1500))


def native(row, observed=True):
    return dict(serial=row['submission_id'], rtp=row['rtp_timestamp'],
                decoder_us=row['decoder_output_us'], submit_us=row['submission_boundary_us'],
                presented_us=str(int(row['submission_boundary_us'])+500) if observed else '0')


class PipelineTests(unittest.TestCase):
    def test_drop_and_missing_callback_are_distinct(self):
        rows = [worker(1, 1000), worker(2, 2000, False), worker(3, 3000), worker(4, 10000)]
        result = pipeline.analyze(rows, [native(rows[0]), native(rows[2], False)], 0, .004)
        # Window starts at first submission; include subsequent arrivals only.
        self.assertEqual(result['arrivals'], 2)
        self.assertEqual(result['submissions'], 1)
        self.assertEqual(result['confirmed_presentations'], 0)
        self.assertEqual(result['dispositions']['queue_stale'], 1)
        self.assertTrue(result['complete_window'])

    def test_join_rejects_wrong_epoch(self):
        rows = [worker(1, 1000), worker(2, 2000), worker(3, 10000)]
        wrong = native(rows[1]); wrong['rtp'] = '999'
        with self.assertRaisesRegex(ValueError, 'identity mismatch'):
            pipeline.analyze(rows, [native(rows[0]), wrong], 0, .004)

    def test_wrap_and_incomplete_window(self):
        rows = [worker(1, 1000), worker(2, 2000, frame=0xffffffff), worker(3, 3000, frame=0)]
        result = pipeline.analyze(rows, list(map(native, rows)), 0, .004)
        self.assertEqual(result['frame_id_gaps'], 0)
        self.assertEqual(result['confirmed_presentations'], 2)
        self.assertFalse(result['complete_window'])
        self.assertEqual(result['durations_us']['decode']['mean'], 140)
        self.assertEqual(result['durations_us']['submit_to_present']['mean'], 500)

    def test_duplicate_native_serial_rejected(self):
        row = worker(1, 1000)
        with self.assertRaisesRegex(ValueError, 'Duplicate native serial'):
            pipeline.analyze([row], [native(row), native(row)], 0, 1)


if __name__ == '__main__':
    unittest.main()
