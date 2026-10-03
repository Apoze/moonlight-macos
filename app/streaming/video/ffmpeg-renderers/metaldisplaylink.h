#pragma once
#import <AppKit/NSScreen.h>
#include <memory>
#include <cstdint>

struct MetalDisplayTick {
    uint64_t sequence = 0;
    double timestamp = 0, target = 0, observed = 0;
};

// A ProMotion refresh-rate request, independent of Metal drawable ownership.
// The shared worker owns pacing; this link never renders or waits for a frame.
class MetalDisplayRefresh {
public:
    MetalDisplayRefresh();
    ~MetalDisplayRefresh();
    bool start(NSScreen* screen, float refresh); // renderer initialization, main thread
    void setPaused(bool paused);
    void stop();
    MetalDisplayTick latest() const;
private:
    class Impl;
    std::unique_ptr<Impl> m_Impl;
};
