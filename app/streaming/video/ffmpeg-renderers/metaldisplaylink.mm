#include "metaldisplaylink.h"
#import <QuartzCore/QuartzCore.h>
#include <mutex>

struct MetalDisplayTickState {
    std::mutex mutex;
    MetalDisplayTick tick;
};

// CADisplayLink requests ProMotion cadence without acquiring Metal drawables.
// A CAMetalDisplayLink drawable forbids presentAfterMinimumDuration; mixing
// that link with nextDrawable on the same layer is also invalid.
API_AVAILABLE(macos(14.0))
@interface MoonlightRefreshTarget : NSObject
- (instancetype)initWithState:(std::shared_ptr<MetalDisplayTickState>)state;
- (void)displayLinkDidFire:(CADisplayLink*)link;
@end

@implementation MoonlightRefreshTarget {
    std::shared_ptr<MetalDisplayTickState> _state;
}
- (instancetype)initWithState:(std::shared_ptr<MetalDisplayTickState>)state
{
    if ((self = [super init])) _state = std::move(state);
    return self;
}
- (void)displayLinkDidFire:(CADisplayLink*)link
{
    // Only publish native clock evidence. No renderer pointer or frame queue.
    std::lock_guard<std::mutex> lock(_state->mutex);
    _state->tick = {_state->tick.sequence + 1, link.timestamp,
                    link.targetTimestamp, CACurrentMediaTime()};
}
@end

class MetalDisplayRefresh::Impl {
public:
    bool start(NSScreen* screen, float refresh)
    {
        if (@available(macOS 14, *)) {
            if (m_Link) return true;
            if (!screen || refresh <= 0) return false;
            auto target = [[MoonlightRefreshTarget alloc] initWithState:m_State];
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
        if (paused) clear();
    }

    void stop()
    {
        if (@available(macOS 14, *)) {
            [m_Link invalidate];
            [m_Link release];
            m_Link = nil;
        }
        clear();
    }
    MetalDisplayTick latest() const {
        std::lock_guard<std::mutex> lock(m_State->mutex);
        return m_State->tick;
    }
    ~Impl() { stop(); }
private:
    void clear() {
        std::lock_guard<std::mutex> lock(m_State->mutex);
        m_State->tick = {};
    }
    std::shared_ptr<MetalDisplayTickState> m_State = std::make_shared<MetalDisplayTickState>();
    CADisplayLink* m_Link API_AVAILABLE(macos(14.0)) = nil;
};

MetalDisplayRefresh::MetalDisplayRefresh() : m_Impl(new Impl) {}
MetalDisplayRefresh::~MetalDisplayRefresh() = default;
bool MetalDisplayRefresh::start(NSScreen* screen, float refresh) { return m_Impl->start(screen, refresh); }
void MetalDisplayRefresh::setPaused(bool paused) { m_Impl->setPaused(paused); }
void MetalDisplayRefresh::stop() { m_Impl->stop(); }
MetalDisplayTick MetalDisplayRefresh::latest() const { return m_Impl->latest(); }
