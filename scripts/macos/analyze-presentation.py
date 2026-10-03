#!/usr/bin/env python3
"""Analyze one explicitly selected Metal CSV; macOS events, not photon timing."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


def distribution(values):
    if not values:
        return None
    values = sorted(values)
    def percentile(p):
        position = (len(values) - 1) * p
        lo = math.floor(position)
        hi = math.ceil(position)
        return round(values[lo] + (values[hi] - values[lo]) * (position - lo), 3)
    return dict(count=len(values), mean=round(sum(values) / len(values), 3),
                p50=percentile(.50), p95=percentile(.95), p99=percentile(.99), max=round(values[-1], 3))


def analyze(path, warmup, duration):
    data = path.read_bytes()
    rows = list(csv.DictReader(data.decode().splitlines()))
    if not rows:
        raise ValueError('Trace has no submissions')
    origin = int(rows[0]['submit_us'])
    selected = [r for r in rows if warmup <= (int(r['submit_us']) - origin) / 1e6 < warmup + duration]
    good = [r for r in selected if int(r['presented_us']) > 0]
    trace_seconds = (int(rows[-1]['submit_us']) - origin) / 1e6
    complete_window = not math.isfinite(duration) or trace_seconds >= warmup + duration
    intervals, jerk, source, delays, decoded = [], [], [], [], []
    previous = None
    previous_interval = None
    for r in good:
        now = float(r['presented_media_s'])
        delays.append((now - float(r['submit_media_s'])) * 1000)
        if int(r['decoder_us']) > 0:
            decoded.append((int(r['presented_us']) - int(r['decoder_us'])) / 1000)
        if previous:
            interval = (now - float(previous['presented_media_s'])) * 1000
            # Missing or reordered records break jerk/source pairs rather than
            # silently joining unrelated observations. Count them separately.
            consecutive = int(r['serial']) == int(previous['serial']) + 1
            if interval > 0 and consecutive:
                intervals.append(interval)
                if previous_interval is not None:
                    jerk.append(abs(interval - previous_interval))
                previous_interval = interval
                delta = (int(r['rtp']) - int(previous['rtp'])) & 0xffffffff
                if 0 < delta < 90000:
                    source.append(delta / 90)
            else:
                previous_interval = None
        previous = r
    elapsed = (float(good[-1]['presented_media_s']) - float(good[0]['presented_media_s'])) if len(good) > 1 else 0
    return dict(path=str(path.resolve()), sha256=hashlib.sha256(data).hexdigest(),
                measurement='macOS drawable presentation events; not physical scanout or click-to-photon',
                warmup_seconds=warmup, window_seconds=duration if math.isfinite(duration) else None,
                trace_first_serial=int(rows[0]['serial']), trace_duration_seconds=round(trace_seconds, 3),
                complete_window=complete_window, submissions=len(selected), valid_presentations=len(good),
                unavailable_or_pending=len(selected)-len(good),
                confirmed_event_fps=round((len(good)-1)/elapsed, 3) if elapsed > 0 else None,
                presentation_coverage_percent=round(100*len(good)/len(selected), 3) if selected else None,
                cadence_representative=complete_window and len(good) >= 100 and len(good) >= .99*len(selected),
                interval_ms=distribution(intervals), jerk_ms=distribution(jerk),
                jerk_over_2ms_percent=round(100*sum(v > 2 for v in jerk)/len(jerk), 3) if jerk else None,
                source_interval_ms=distribution(source), submit_to_present_ms=distribution(delays),
                decoder_output_to_present_ms=distribution(decoded),
                max_clock_uncertainty_us=max((int(r['uncertainty_us']) for r in good), default=None))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('trace', type=Path)
    parser.add_argument('--warmup', type=float, default=10)
    parser.add_argument('--duration', type=float, default=float('inf'))
    args = parser.parse_args()
    if args.warmup < 0 or args.duration <= 0:
        parser.error('warmup must be nonnegative and duration positive')
    print(json.dumps(analyze(args.trace, args.warmup, args.duration), indent=2))
