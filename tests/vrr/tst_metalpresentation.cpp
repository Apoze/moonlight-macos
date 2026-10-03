#include "../../app/streaming/video/ffmpeg-renderers/metalpresentation.h"
#include <cstdio>
#include <limits>
#include <memory>
#include <thread>

int main()
{
    using namespace MetalPresentation;
    int failures = 0;
    auto check = [&](bool ok, const char* message) {
        if (!ok) { std::fprintf(stderr, "FAIL: %s\n", message); ++failures; }
    };
    ClockSample clock{500, 100000, 100002};
    check(clock.translate(500.01, 120000) >= 110000, "translate independent clock epochs");
    check(clock.translate(0, 120000) == 0, "skipped drawable has no presentation time");
    check(clock.translate(std::numeric_limits<double>::quiet_NaN(), 120000) == 0, "reject NaN");
    check(clock.translate(501, 120000) == 0, "reject future timestamp");
    check(ClockSample{500, 100000, 102000}.translate(500.01, 120000) == 0, "reject wide correlation");
    auto state = std::make_shared<State>(2);
    Record frame;
    frame.submitUs = 100000; frame.submitMedia = 500;
    auto first = state->submit(frame);
    auto second = state->submit(frame);
    state->presented(second, 500.02, 125000, clock);
    state->presented(first, 500.01, 126000, clock);
    check(state->latest().serial == second, "late callback cannot regress latest observation");
    check(state->snapshot().front().presentedUs > 0, "retain out-of-order callback by identity");
    auto third = state->submit(frame);
    state->presented(first, 500.03, 140000, clock);
    check(!state->snapshot().back().callback, "old callback cannot corrupt overwritten record");
    state->presented(third, 0, 140000, clock);
    check(state->snapshot().back().callback && !state->snapshot().back().presentedUs, "preserve unavailable callback");
    check(state->snapshot().size() == 2, "storage remains bounded");
    auto fourth = state->submit(frame);
    state->presented(fourth, 499.99, 140000, clock);
    check(state->snapshot().back().presentedUs == 0, "reject pre-submission timestamp");
    std::weak_ptr<State> weak = state;
    std::thread callback([retained = state, clock, frame] {
        for (int i = 0; i < 1000; ++i) {
            auto serial = retained->submit(frame);
            retained->presented(serial, 500.01, 130000, clock);
        }
    });
    for (int i = 0; i < 1000; ++i) state->snapshot();
    state.reset(); callback.join();
    check(weak.expired(), "callback owns state safely past renderer lifetime then releases it");
    return failures ? 1 : 0;
}
