#!/usr/bin/env python3
"""Analyze standalone Metal probe stages; no network, decoder or optical latency."""
import argparse
import csv
import importlib.util
import json
import math
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    'presentation', Path(__file__).with_name('analyze-presentation.py'))
presentation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(presentation)


def stages(rows):
    completed = [r for r in rows if int(r['gpu_status']) == 4]
    timed = [r for r in completed if 0 < float(r['gpu_start_s']) <= float(r['gpu_end_s'])]
    shown = [r for r in rows if float(r['presented_media_s']) > 0]
    requested = [r for r in rows if float(r['present_requested_s']) > 0]
    def difference(items, end, start):
        return presentation.distribution([
            1000 * (float(r[end]) - float(r[start])) for r in items])
    return dict(
        gpu_completed=len(completed),
        gpu_errors=sum(int(r['gpu_status']) == 5 for r in rows),
        gpu_pending=sum(int(r['gpu_status']) not in (4, 5) for r in rows),
        gpu_timestamps_available=len(timed),
        presentation_callback_with_zero_time=sum(
            int(r['callback']) == 1 and float(r['presented_media_s']) == 0 for r in rows),
        presentation_callback_pending=sum(int(r['callback']) == 0 for r in rows),
        inactive=sum(int(r['active']) == 0 for r in rows),
        not_visible=sum(int(r['visible']) == 0 for r in rows),
        cpu_submit_after_deadline=sum(
            float(r['submit_media_s']) > float(r['deadline_s']) for r in rows),
        present_request_pending=len(rows) - len(requested),
        present_request_after_deadline=sum(
            float(r['present_requested_s']) > float(r['deadline_s']) for r in requested),
        gpu_end_after_expected_presentation=sum(
            float(r['gpu_end_s']) > float(r['expected_s']) for r in timed),
        cpu_encode_ms=difference(rows, 'submit_media_s', 'ready_s'),
        gpu_execution_ms=difference(timed, 'gpu_end_s', 'gpu_start_s'),
        submit_to_gpu_start_ms=difference(timed, 'gpu_start_s', 'submit_media_s'),
        submit_deadline_margin_ms=difference(rows, 'deadline_s', 'submit_media_s'),
        present_request_deadline_margin_ms=difference(requested, 'deadline_s', 'present_requested_s'),
        presented_minus_expected_ms=difference(shown, 'presented_media_s', 'expected_s'),
        presentation_callback_delay_ms=difference(
            [r for r in shown if float(r['presented_callback_s']) > 0],
            'presented_callback_s', 'presented_media_s'))


def analyze(path, warmup, duration):
    summary = presentation.analyze(path, warmup, duration)
    with path.open() as source:
        rows = list(csv.DictReader(source))
    origin = int(rows[0]['submit_us'])
    selected = [r for r in rows if
                warmup <= (int(r['submit_us']) - origin) / 1e6 < warmup + duration]
    summary.pop('decoder_output_to_present_ms')
    summary.pop('source_interval_ms')
    summary['measurement'] = 'Synthetic Metal presentation events; no video decoder or physical scanout'
    summary['stages'] = stages(selected)
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('--warmup', type=float, default=10)
    parser.add_argument('--duration', type=float, default=30)
    args = parser.parse_args()
    if not math.isfinite(args.warmup) or args.warmup < 0 or not math.isfinite(args.duration) or args.duration <= 0:
        parser.error('warmup must be finite and nonnegative; duration finite and positive')
    print(json.dumps(analyze(args.trace, args.warmup, args.duration), indent=2))
