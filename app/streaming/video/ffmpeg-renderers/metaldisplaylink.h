#pragma once
#import <AppKit/NSScreen.h>
#include <memory>

// A ProMotion refresh-rate request, independent of Metal drawable ownership.
// The shared worker owns pacing; this link never renders or waits for a frame.
class MetalDisplayRefresh {
public:
    MetalDisplayRefresh();
    ~MetalDisplayRefresh();
    bool start(NSScreen* screen, float refresh); // renderer initialization, main thread
    void setPaused(bool paused);
    void stop();
private:
    class Impl;
    std::unique_ptr<Impl> m_Impl;
};
