# Metal presentation on macOS

## Design and evidence boundaries

The Metal backend implements the current `IVrrFramePresenter` contract. The
shared Nonary worker remains the only source-timestamp scheduler. No controller
constants are changed. Preparation imports the decoded VideoToolbox image,
renders using the same encoder as fixed presentation, submits GPU work, and
observes completion with a 50 ms bound. The worker then holds until its target;
presentation submits the completed drawable with `displaySyncEnabled=YES`.
On ProMotion, an NSScreen-bound `CADisplayLink` requests the display's maximum
cadence. Its callback performs no work and holds no renderer pointer. The
shared worker acquires exclusively through `CAMetalLayer.nextDrawable`; no
CAMetalDisplayLink is attached to that layer. Presentation uses synchronized
`present` after the worker's source-timing hold, without another timer or native
minimum-duration queue. The screen-bound link survives initial color setup and
later format changes; only the legacy layer-bound display link is stopped for
those changes. Pausing suspends the refresh request, and fallback/teardown
invalidates it. Tested minimum-duration and explicit phase-target variants
increased latency and/or dropped frames, so they are not retained.
Continuously adaptive displays use synchronized `present` after the worker's
hold. They remain untested in this internal-display phase.

The adaptive layer owns at most two drawables (the fixed control uses three). This does not add a queue of decoded
video frames. Acquisition uses Apple's timeout-enabled `nextDrawable` (the
timeout is controlled by Core Animation, approximately one second), not an
unbounded polling loop. A missing drawable skips that image.
A GPU timeout/error requests renderer recovery. Cancellation releases the
prepared drawable without displaying it. Source AVFrames and CoreVideo texture
wrappers remain owned through GPU completion, including after a timeout.
Completion handlers retain their own resources, never a renderer pointer.
Size/display transitions recreate the renderer and resample eligibility.

Synchronized Metal presentation honors latch protection without changing
tearing modes. Native backend ID 4 denotes Metal in the shared trace. Metal's
`present` method returns void, so native result-code fields stay unavailable.
Presentation IDs are client serials correlated with actual drawable IDs in the
Metal sidecar. Asynchronous observations may describe an earlier submission.

On the built-in M5 Pro display, NSScreen reports approximately 8.333–41.667 ms
refresh intervals and 4.167 ms update granularity. This is discrete ProMotion
cadence. A nonzero refresh range alone does **not** mean continuously variable
Adaptive-Sync, and successful submission does not prove physical scanout.
The synchronized path lets macOS choose presentation; it cannot guarantee
uniform spacing for every arbitrary source rate. External-display behavior,
HDR, other GPUs, and optical input-to-photon latency require separate tests.

## Measurements

`MOONLIGHT_METAL_TRACE=/absolute/ignored/path/prefix` enables a bounded in-memory
ring of 65,536 native submissions. Without tracing the ring holds 256 records
for asynchronous worker feedback. There is no disk write per frame. Renderer
teardown exports a uniquely suffixed CSV; `serial > 1` in the first row exposes
ring truncation. Pending callbacks remain marked unavailable at export, and
callbacks after teardown can safely finish against their retained state.

The callback records `MTLDrawable.presentedTime`, the callback receipt time,
the drawable ID and source RTP timestamp. Core Animation host seconds are
correlated with the Limelight monotonic clock using a bracket around
`CACurrentMediaTime()` for each submission. Invalid, non-finite, pre-submission,
future, very stale, and wide-bracket timestamps are rejected. A zero native
timestamp is unavailable/skipped, never a zero-latency observation. The sidecar
retains both raw clocks and correlation uncertainty.

```sh
MOONLIGHT_METAL_TRACE="$PWD/.runtime/builtin/metal-tests/adaptive60" \
  ./scripts/macos/launch-builtin.command stream PC-Mazino Desktop \
  --vrr --fps 60 --resolution 1920x1200 --bitrate 30000 --quit-after
python3 scripts/macos/analyze-presentation.py /exact/capture.csv \
  --warmup 10 --duration 30
```

The analysis reports interval/jerk distributions, jerk over 2 ms, confirmed native
presentation-event rate and observation coverage, submission-to-presentation and decoder-output-to-presentation
latency. These are macOS presentation events, **not** optical scanout or
click-to-photon. Source interval statistics concern only the presented subset;
use the ordinary VRR trace and server capture for source-side loss attribution.
Missing observations break interval/jerk sequences rather than bridging gaps.
With less than 99% usable presentation timestamps, the analysis marks cadence
unrepresentative; the rate of available events must not be called display FPS.
Latency quantiles then concern only the observed subset.

For a controlled comparison, set `MOONLIGHT_METAL_FIXED_CONTROL=1` on the same
command, still with `--vrr`. This uses the fixed Metal display-link path locally
while retaining `clientVrrRequested=1` on the server. Comparing against `--no-vrr`
also changes Vibepollo capture policy and is an end-to-end comparison, not a
renderer-only experiment. Keep codec, bitrate, resolution, source animation,
overlay state, warmup, and sampled duration matched. Do not compile during the
measurement window. A browser animation measures its actual rAF cadence; a
requested rate alone is not proof of uniform source frames.

## Validation status — 2026-10-03

**Experimental: the smoothness/throughput acceptance goal is not met.**
Do not infer a production-ready ProMotion implementation from compilation,
a successful stream, a VRR overlay, or passing controller replay. The saved
reference profile remains fixed-pacing/VRR-off. The development bundle is
separate from the system application. External display and PyroWave work have
not started.

Final candidate: CADisplayLink requesting 120 Hz, synchronized immediate
presentation, two drawables, shared balanced VRR controller. Internal M5 Pro
panel only; macOS 26.6.2; HEVC hardware decode, 1920×1200, 30 Mbit/s, SDR.
AC power was temporarily Automatic (low-power API false, thermal state nominal).
The original AC low-power setting was restored after testing; battery power
mode was unchanged. The Windows server is idle, its virtual display/RTSS state
was restored, and the temporary test HTTP server was stopped.
Xcode changed from 26.6/SDK26.5 to 27.0/SDK27 during the experiments; the final
candidate and all seven test suites were rebuilt from fresh build directories.

The following are 30-second native presentation-event windows, with 100% valid
presentation timestamps for submitted images in each window. They are not
physical scanout or click-to-photon measurements. Wall-clock source windows
are matched approximately using the client startup log (second precision);
source browser exports independently confirm the steady requested cadence.

| Requested FPS | Native event FPS | Native interval p95 / p99, ms | Decode output → presentation mean / p95, ms |
|---:|---:|---:|---:|
| 60 | 59.992 | 25.000 / 33.333 | 31.899 / 40.808 |
| 100 | 93.172 | 16.667 / 41.667 | 33.427 / 47.062 |
| 116 | 102.976 | 16.667 / 16.669 | 37.888 / 47.021 |

At 60 FPS the mean rate is correct but short/long interval alternation remains.
At 100 and 116 the client does not deliver the entire steady source cadence.
ProMotion's discrete display periods explain why arbitrary rates cannot have
uniform intervals, but do not by themselves explain or excuse all observed
client drops and stalls. Their attribution needs further work; no smoothness
or latency improvement is claimed for release use.

Reproduce the exact native windows with `analyze-presentation.py` and these
ignored local captures (warmup/duration in seconds):

- `final60-71652-1791036536758.csv`: 18 / 30, SHA256
  `33ca98d0ef04d3f4436108363e56d562fa4216ceb3e95119a640ddf87b900b6a`.
- `final100-71760-1791036655559.csv`: 25 / 30, SHA256
  `896ea812d587e32ba2d1006f4e27a69736477c5ca5f4be60acc289129ae0ef7c`.
- `final116-71895-1791036781394.csv`: 34 / 30, SHA256
  `570b65f9d2363b732bf7a8d04b2feb609aee62ee492827472ae9fa2cb7f7c5e0`.

The final 60/100/116 traces and post-transition 116 trace pass
`vrrreplay --require-exact-baseline`. Replay now validates admission against the
captured `playout_queue_frames` limit (four here), not a hardcoded three;
Metal's void native result and asynchronous display-event observations have
explicit backend semantics. This reproduces controller decisions, not photons.

Full-screen exit/return recreated the renderer and resumed presentation.
Minimize/restore returned to the stream; stopping completed normally and the
server acknowledged cancellation. These are short lifecycle checks, not an
exhaustive occlusion, sleep/wake, HDR, device-loss or multi-monitor certification.

Rejected prototypes are retained only as ignored local evidence. A
CAMetalDisplayLink/minimum-duration combination threw a native API exception;
that API combination is absent from the final code. Early CADisplayLink trials
incorrectly invalidated the link during first-frame color initialization and
cannot validate an active refresh request. After correcting that lifecycle,
explicit phase targets still degraded throughput/latency and were removed.
No abandoned scheduling experiment remains enabled.

To finish acceptance, investigate native presentation versus worker readiness
and drops with repeatable captures on the internal panel, then compare a
correct display-synchronized ProMotion policy with continuous Adaptive-Sync
policy. Avoid changing shared controller constants just to hide missed frames.
Optical latency requires an external camera/sensor protocol and remains open.

## Sources reviewed

- [Apple: Optimize for variable refresh rate displays](https://developer.apple.com/videos/play/wwdc2021/10147/)
  describes native Metal presentation and Adaptive-Sync eligibility.
- [Apple: displayUpdateGranularity](https://developer.apple.com/documentation/appkit/nsscreen/displayupdategranularity)
  distinguishes continuous from discrete update rates.
- [Apple: presentedTime](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime)
  and the installed Xcode SDK `MTLDrawable.h` define presentation callbacks
  and the zero timestamp for unpresented/skipped images.
- [Apple: CAMetalDisplayLink](https://developer.apple.com/documentation/quartzcore/cametaldisplaylink)
  supplies pre-acquired drawables. A runtime check on macOS 26.6 rejects
  `presentAfterMinimumDuration` on those drawables; the rejected prototype is
  excluded from this implementation. `CADisplayLink` keeps refresh requests
  independent of drawable ownership.
- [Nonary PR 3](https://github.com/Nonary/moonlight-qt/pull/3), head `513e5382`:
  reviewed, not cherry-picked. It uses an older preparation contract and waits
  for the display-link callback after the controller's target.
- [Andy Grundman's Metal branch](https://github.com/andygrundman/moonlight-qt/tree/andyg.macos-metal-frame-pacing),
  reviewed at `57088f1a`: useful native telemetry and ProMotion distinction;
  its separate scheduler/UI architecture is not imported.
