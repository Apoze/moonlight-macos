// Isolate native presentation from decoding, networking and the VRR worker.
// macOS 14+: FPS SECONDS OUTPUT.csv [FRAME_LATENCY [window|fullscreen [metal|screen [timed]]]]
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <cmath>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <memory>
#include <mutex>
#include <vector>

struct Sample {
    uint64_t serial;
    double ready, submitted, deadline, expected, presented = 0;
    bool callback = false;
    bool visible = false, active = false;
    double presentedCallback = 0, gpuStart = 0, gpuEnd = 0, gpuCallback = 0;
    long gpuStatus = 0;
    double presentRequested = 0;
};
struct Samples { std::mutex lock; std::vector<Sample> rows; bool invalidDisplay = false; };

// Let AppKit own layer geometry, without MTKView's separate drawable lifecycle.
@interface ProbeView : NSView
@end
@implementation ProbeView
- (CALayer*)makeBackingLayer { return [CAMetalLayer layer]; }
- (BOOL)wantsUpdateLayer { return YES; }
@end

API_AVAILABLE(macos(14.0))
@interface CadenceProbe : NSObject <CAMetalDisplayLinkDelegate>
- (instancetype)initWithWindow:(NSWindow*)window screen:(NSScreen*)screen
                         state:(std::shared_ptr<Samples>)state timed:(bool)timed;
- (void)screenDisplayLink:(CADisplayLink*)link;
@end
@implementation CadenceProbe {
    NSWindow* _window;
    CGDirectDisplayID _display;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    std::shared_ptr<Samples> _state;
    bool _timed;
}
- (instancetype)initWithWindow:(NSWindow*)window screen:(NSScreen*)screen
                         state:(std::shared_ptr<Samples>)state timed:(bool)timed
{
    if ((self = [super init])) {
        _window = window;
        _display = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        _state = state;
        _timed = timed;
        _queue = [((CAMetalLayer*)window.contentView.layer).device newCommandQueue];
        // Real moving geometry keeps this control distinct from an almost
        // static clear color and makes the local test recognizable onscreen.
        NSString* source = @"#include <metal_stdlib>\nusing namespace metal;\n"
            "struct V { float4 p [[position]]; };\n"
            "vertex V moveBar(uint i [[vertex_id]], constant float& x [[buffer(0)]]) {\n"
            " const float2 p[4] = {float2(-.025,-.8),float2(-.025,.8),float2(.025,-.8),float2(.025,.8)};\n"
            " return {float4(p[i].x+x,p[i].y,0,1)}; }\n"
            "fragment float4 barColor() { return float4(.15,.75,.95,1); }\n";
        NSError* error = nil;
        auto library = [_queue.device newLibraryWithSource:source options:nil error:&error];
        auto description = [[MTLRenderPipelineDescriptor alloc] init];
        auto vertex = [library newFunctionWithName:@"moveBar"];
        auto fragment = [library newFunctionWithName:@"barColor"];
        description.vertexFunction = vertex; description.fragmentFunction = fragment;
        description.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        _pipeline = [_queue.device newRenderPipelineStateWithDescriptor:description error:&error];
        [vertex release]; [fragment release]; [description release]; [library release];
        if (!_pipeline) { _state->invalidDisplay = true; NSLog(@"INVALID: probe pipeline %@", error); }
    }
    return self;
}
- (void)dealloc { [_pipeline release]; [_queue release]; [super dealloc]; }
- (void)metalDisplayLink:(CAMetalDisplayLink*)link needsUpdate:(CAMetalDisplayLinkUpdate*)update
{
    [self renderDrawable:update.drawable link:link deadline:update.targetTimestamp
                expected:update.targetPresentationTimestamp];
}
- (void)screenDisplayLink:(CADisplayLink*)link
{
    // This mode never creates a CAMetalDisplayLink on the layer.
    auto drawable = [(CAMetalLayer*)_window.contentView.layer nextDrawable];
    [self renderDrawable:drawable link:link deadline:link.targetTimestamp expected:link.targetTimestamp];
}
- (void)renderDrawable:(id<CAMetalDrawable>)drawable link:(id)link
             deadline:(double)deadline expected:(double)expected
{
    NSScreen* screen = _window.screen;
    const auto display = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    const NSRect video = [_window convertRectToScreen:
        [_window.contentView convertRect:_window.contentView.bounds toView:nil]];
    if (!screen || display != _display || !CGDisplayIsBuiltin(display) ||
        !CGDisplayIsActive(display) || !NSContainsRect(screen.frame, video) ||
        CGDisplayIsInMirrorSet(display)) {
        { std::lock_guard<std::mutex> lock(_state->lock); _state->invalidDisplay = true; }
        NSLog(@"INVALID: builtin=%u actual=%u screen=%@ window=%@ video=%@", _display, display,
            NSStringFromRect(screen.frame), NSStringFromRect(_window.frame), NSStringFromRect(video));
        [link setPaused:YES];
        return;
    }
    const double ready = CACurrentMediaTime();
    if (!drawable) return;
    auto buffer = [_queue commandBuffer];
    auto pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(.04, .08, .14, 1);
    auto encoder = [buffer renderCommandEncoderWithDescriptor:pass];
    const float position = .8f * sin(expected * 1.5);
    [encoder setRenderPipelineState:_pipeline];
    [encoder setVertexBytes:&position length:sizeof(position) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    [encoder endEncoding];
    const auto state = _state;
    const bool timed = _timed;
    size_t index;
    {
        std::lock_guard<std::mutex> lock(state->lock);
        index = state->rows.size();
        state->rows.push_back({index + 1, ready, CACurrentMediaTime(),
                              deadline, expected, 0, false,
                              bool(_window.occlusionState & NSWindowOcclusionStateVisible), bool(NSApp.active)});
    }
    [drawable addPresentedHandler:^(id<MTLDrawable> shown) {
        std::lock_guard<std::mutex> lock(state->lock);
        state->rows[index].presented = shown.presentedTime;
        state->rows[index].callback = true;
        state->rows[index].presentedCallback = CACurrentMediaTime();
    }];
    [buffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        const double receipt = CACurrentMediaTime();
        std::lock_guard<std::mutex> lock(state->lock);
        auto& row = state->rows[index];
        row.gpuStart = completed.GPUStartTime;
        row.gpuEnd = completed.GPUEndTime;
        row.gpuStatus = completed.status;
        row.gpuCallback = receipt;
    }];
    // Equivalent to MTLCommandBuffer.presentDrawable:, with the request time
    // recorded. Direct present immediately after commit can race scheduling.
    // Both native clock modes share this exact render/presentation operation.
    [buffer addScheduledHandler:^(id<MTLCommandBuffer>) {
        const double requested = CACurrentMediaTime();
        if (timed) [drawable presentAtTime:expected];
        else [drawable present];
        std::lock_guard<std::mutex> lock(state->lock);
        state->rows[index].presentRequested = requested;
    }];
    [buffer commit];
}
@end

int main(int argc, char** argv) { @autoreleasepool {
    if (argc < 4 || argc > 8) return 2;
    const int fps = atoi(argv[1]), seconds = atoi(argv[2]);
    const int latency = argc >= 5 ? atoi(argv[4]) : 1;
    const bool fullscreen = argc >= 6 && strcmp(argv[5], "fullscreen") == 0;
    const bool screenDriver = argc >= 7 && strcmp(argv[6], "screen") == 0;
    const bool timed = argc == 8 && strcmp(argv[7], "timed") == 0;
    if ((fps != 60 && fps != 120) || seconds < 5 || seconds > 120 ||
        (latency != 1 && latency != 2) ||
        (argc >= 6 && !fullscreen && strcmp(argv[5], "window") != 0) ||
        (argc >= 7 && !screenDriver && strcmp(argv[6], "metal") != 0) ||
        (screenDriver && latency != 1) || (argc == 8 && (!timed || !screenDriver))) return 2;
    if (@available(macOS 14, *)) {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        NSScreen* builtin = nil;
        for (NSScreen* screen in NSScreen.screens) {
            const auto id = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            if (CGDisplayIsBuiltin(id) && CGDisplayIsActive(id) && !CGDisplayIsInMirrorSet(id)) builtin = screen;
        }
        if (!builtin) return 3;
        NSWindow* window = [[NSWindow alloc] initWithContentRect:builtin.frame
            styleMask:fullscreen ? (NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable)
                                 : NSWindowStyleMaskBorderless
            backing:NSBackingStoreBuffered defer:NO screen:builtin];
        window.title = @"Local Metal cadence probe";
        window.opaque = YES; window.hasShadow = NO;
        [window setFrame:builtin.frame display:NO];
        if (window.screen != builtin || !NSContainsRect(builtin.frame, window.frame)) return 4;
        NSLog(@"PROBE fps=%d latency=%d fullscreen=%d builtin=%@ actual=%@ window=%@ lowPower=%d thermal=%ld backing=%.1f screenScale=%.1f", fps, latency, fullscreen,
            builtin.deviceDescription[@"NSScreenNumber"], window.screen.deviceDescription[@"NSScreenNumber"],
            NSStringFromRect(window.frame), NSProcessInfo.processInfo.lowPowerModeEnabled,
            (long)NSProcessInfo.processInfo.thermalState, window.backingScaleFactor, builtin.backingScaleFactor);
        auto device = MTLCreateSystemDefaultDevice();
        auto view = [[ProbeView alloc] initWithFrame:window.contentView.bounds];
        view.wantsLayer = YES;
        view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        window.contentView = view;
        auto layer = (CAMetalLayer*)view.layer;
        layer.device = device;
        [device release];
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.opaque = YES; layer.framebufferOnly = YES;
        layer.maximumDrawableCount = 3; layer.displaySyncEnabled = YES;
        layer.shouldRasterize = NO;
        layer.contentsScale = window.backingScaleFactor;
        layer.drawableSize = [view convertSizeToBacking:view.bounds.size];
        [view release];
        [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
        if (fullscreen) {
            window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
            [window toggleFullScreen:nil];
        }
        auto state = std::make_shared<Samples>();
        state->rows.reserve(fps * (seconds + 2));
        auto delegate = [[CadenceProbe alloc] initWithWindow:window screen:builtin state:state timed:timed];
        id link;
        if (screenDriver) {
            auto screenLink = [builtin displayLinkWithTarget:delegate selector:@selector(screenDisplayLink:)];
            screenLink.preferredFrameRateRange = CAFrameRateRangeMake(fps, fps, fps);
            link = [screenLink retain];
        } else {
            auto metalLink = [[CAMetalDisplayLink alloc] initWithMetalLayer:layer];
            metalLink.delegate = delegate; metalLink.preferredFrameLatency = latency;
            metalLink.preferredFrameRateRange = CAFrameRateRangeMake(fps, fps, fps);
            link = metalLink;
        }
        NSLog(@"PROBE driver=%@ timed=%d", screenDriver ? @"CADisplayLink" : @"CAMetalDisplayLink", timed);
        // Allow AppKit's fullscreen transition to complete before sampling.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (fullscreen ? 3 : 0) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (fullscreen && !(window.styleMask & NSWindowStyleMaskFullScreen)) {
                state->invalidDisplay = true;
                NSLog(@"INVALID: native fullscreen transition did not complete");
            }
            layer.drawableSize = [window.contentView convertSizeToBacking:window.contentView.bounds.size];
            if (!state->invalidDisplay) [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, seconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [link invalidate];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                [NSApp stop:nil];
                [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
                    location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                    subtype:0 data1:0 data2:0] atStart:NO];
            });
            });
        });
        [NSApp run];
        std::lock_guard<std::mutex> lock(state->lock);
        std::ofstream out(argv[3]); out << std::setprecision(16);
        // No decoder exists in this probe. Keep compatibility with the native
        // presentation analyzer without inventing decoder or source timestamps.
        out << "serial,rtp,decoder_us,submit_us,presented_us,uncertainty_us,callback,deadline_s,expected_s,submit_media_s,presented_media_s,visible,active,ready_s,presented_callback_s,gpu_start_s,gpu_end_s,gpu_callback_s,gpu_status,present_requested_s\n";
        for (const auto& r : state->rows)
            out << r.serial << ",0,0," << uint64_t(r.submitted * 1e6) << ',' << uint64_t(r.presented * 1e6)
                << ",0," << r.callback << ',' << r.deadline << ',' << r.expected
                << ',' << r.submitted << ',' << r.presented << ',' << r.visible << ',' << r.active
                << ',' << r.ready << ',' << r.presentedCallback << ',' << r.gpuStart << ',' << r.gpuEnd
                << ',' << r.gpuCallback << ',' << r.gpuStatus << ',' << r.presentRequested << '\n';
        if (!screenDriver) [(CAMetalDisplayLink*)link setDelegate:nil];
        [link release]; [delegate release]; [window close];
        return state->invalidDisplay ? 6 : out.good() ? 0 : 5;
    }
    return 3;
}}
