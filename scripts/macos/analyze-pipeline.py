#!/usr/bin/env python3
"""Attribute a decoded-frame cohort using one worker trace and its Metal sidecar.

Expand .vrrtrace with scripts/decode-vrr-trace.py first. Never combine renderer
epochs: submission IDs restart. RTP + decoder timestamp verify every join.
All durations use the client's monotonic clock, never a server wall clock.
"""
import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path


def read_rows(path):
    with Path(path).open() as stream:
        return list(csv.DictReader(line for line in stream if not line.startswith('#')))


def distribution(values):
    values = sorted(values)
    if not values:
        return None
    return dict(count=len(values), mean=sum(values) / len(values),
                p50=values[(len(values)-1)//2],
                p95=values[int((len(values)-1)*.95)],
                p99=values[int((len(values)-1)*.99)], maximum=values[-1])


def analyze(worker, native, warmup, duration):
    if not worker or not native or warmup < 0 or duration <= 0:
        raise ValueError('Nonempty traces, nonnegative warmup and positive duration required')
    start = int(native[0]['submit_us']) + round(warmup * 1_000_000)
    end = start + round(duration * 1_000_000)
    by_serial = {}
    for row in native:
        serial = int(row['serial'])
        if serial in by_serial:
            raise ValueError('Duplicate native serial: use a single renderer epoch')
        by_serial[serial] = row
    cohort = sorted((r for r in worker if start <= int(r['pacer_arrival_us']) < end),
                    key=lambda r: int(r['arrival_sequence']))
    metrics = collections.defaultdict(list)
    presented = observed = unmatched = 0
    identities = set()
    for row in cohort:
        identity = int(row['arrival_sequence'])
        if identity in identities:
            raise ValueError('Duplicate worker arrival sequence')
        identities.add(identity)
        if row['presented'] != '1':
            continue
        presented += 1
        for label, left, right in [
            ('assembly', 'frame_reassembled_us', 'frame_receive_us'),
            ('decode_queue', 'decode_submit_us', 'frame_reassembled_us'),
            ('decode', 'decoder_output_us', 'decode_submit_us'),
            ('worker_queue', 'dequeue_us', 'pacer_arrival_us'),
            ('after_prepare_to_submit', 'submission_boundary_us', 'prepare_end_us')]:
            a, b = int(row[left]), int(row[right])
            if a >= b > 0:
                metrics[label].append(a-b)
        for key in ('prepare_acquire_us', 'prepare_render_us', 'prepare_us', 'playout_delay_us'):
            if row['prepare_timing_valid'] == '1':
                metrics[key].append(int(row[key]))
        native_row = by_serial.get(int(row['submission_id'])) if row['submission_id_valid'] == '1' else None
        if native_row is None:
            unmatched += 1
            continue
        if (int(native_row['rtp']) != int(row['rtp_timestamp']) or
                int(native_row['decoder_us']) != int(row['decoder_output_us'])):
            raise ValueError('Native/worker identity mismatch: wrong renderer epoch or capture')
        display = int(native_row['presented_us'])
        if display <= 0:
            continue
        observed += 1
        for label, earlier in [('submit_to_present', int(native_row['submit_us'])),
                               ('decode_to_present', int(row['decoder_output_us'])),
                               ('receive_to_present', int(row['frame_receive_us']))]:
            if display >= earlier > 0:
                metrics[label].append(display-earlier)
    gaps = 0
    backwards = 0
    intervals = collections.defaultdict(list)
    for previous, current in zip(cohort, cohort[1:]):
        delta = (int(current['frame']) - int(previous['frame'])) & 0xffffffff
        if 0 < delta < 0x80000000:
            gaps += delta-1
        else:
            backwards += 1
        if delta == 1:
            for key in ('frame_receive_us', 'frame_reassembled_us', 'decoder_output_us'):
                left, right = int(previous[key]), int(current[key])
                if right >= left > 0:
                    intervals[key].append(right-left)
            rtp_delta = (int(current['rtp_timestamp']) - int(previous['rtp_timestamp'])) & 0xffffffff
            if 0 < rtp_delta < 90000:
                intervals['host_rtp_us'].append(rtp_delta * 1000000 / 90000)
    return dict(
        cohort='pacer arrivals, not display events', start_us=start, end_us=end,
        complete_window=max(int(r['pacer_arrival_us']) for r in worker) >= end,
        arrivals=len(cohort), arrivals_per_second=len(cohort)/duration,
        frame_id_gaps=gaps, frame_id_repeats_or_backwards=backwards,
        dispositions=dict(collections.Counter(r['disposition'] for r in cohort)),
        submissions=presented, confirmed_presentations=observed,
        unmatched_submissions=unmatched,
        native_coverage_of_submissions=observed/presented if presented else None,
        presented_fraction_of_arrivals=observed/len(cohort) if cohort else None,
        durations_us={k: distribution(v) for k, v in metrics.items()},
        consecutive_frame_intervals_us={k: distribution(v) for k, v in intervals.items()},
        receive_gaps_over_40ms=sum(v > 40000 for v in intervals['frame_receive_us']),
        limitations=['Arrival cohort may present outside the selected time window.',
                     'Gaps precede pacer admission; they do not identify server versus network loss.',
                     'Host RTP may be adjusted by the server and is not raw capture timing.',
                     'Native timestamps do not measure physical scanout or input-to-photon.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('worker_csv', type=Path)
    parser.add_argument('native_csv', type=Path)
    parser.add_argument('--warmup', type=float, default=10)
    parser.add_argument('--duration', type=float, default=30)
    args = parser.parse_args()
    result = analyze(read_rows(args.worker_csv), read_rows(args.native_csv), args.warmup, args.duration)
    result['inputs'] = [dict(path=str(p), sha256=hashlib.sha256(p.read_bytes()).hexdigest())
                        for p in (args.worker_csv, args.native_csv)]
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
