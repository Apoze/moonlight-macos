#include "metaldisplaylink.h"
#import <QuartzCore/QuartzCore.h>

// CADisplayLink requests ProMotion cadence without acquiring Metal drawables.
// A CAMetalDisplayLink drawable forbids presentAfterMinimumDuration; mixing
// that link with nextDrawable on the same layer is also invalid.
API_AVAILABLE(macos(14.0))
@interface MoonlightRefreshTarget : NSObject
- (void)displayLinkDidFire:(CADisplayLink*)link;
@end

@implementation MoonlightRefreshTarget
- (void)displayLinkDidFire:(CADisplayLink*)link
{
    // Intentionally no renderer pointer, video queue, GPU work or CPU wait.
}
@end

class MetalDisplayRefresh::Impl {
public:
    bool start(NSScreen* screen, float refresh)
    {
        if (@available(macOS 14, *)) {
            if (m_Link) return true;
            if (!screen || refresh <= 0) return false;
            auto target = [MoonlightRefreshTarget new];
            m_Link = [[screen displayLinkWithTarget:target selector:@selector(displayLinkDidFire:)] retain];
            [target release]; // CADisplayLink owns its target until invalidation.
            if (!m_Link) return false;
            m_Link.preferredFrameRateRange = CAFrameRateRangeMake(refresh, refresh, refresh);
            [m_Link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
            return true;
        }
        return false;
    }

    void setPaused(bool paused)
    {
        if (@available(macOS 14, *)) m_Link.paused = paused;
    }

    void stop()
    {
        if (@available(macOS 14, *)) {
            [m_Link invalidate];
            [m_Link release];
            m_Link = nil;
        }
    }
    ~Impl() { stop(); }
private:
    CADisplayLink* m_Link API_AVAILABLE(macos(14.0)) = nil;
};

MetalDisplayRefresh::MetalDisplayRefresh() : m_Impl(new Impl) {}
MetalDisplayRefresh::~MetalDisplayRefresh() = default;
bool MetalDisplayRefresh::start(NSScreen* screen, float refresh) { return m_Impl->start(screen, refresh); }
void MetalDisplayRefresh::setPaused(bool paused) { m_Impl->setPaused(paused); }
void MetalDisplayRefresh::stop() { m_Impl->stop(); }
