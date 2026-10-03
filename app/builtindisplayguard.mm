#include "builtindisplayguard.h"

#include <QGuiApplication>
#include <QScreen>
#include <QWindow>
#include <QTimer>
#include <QtDebug>
#include <QtGui/qscreen_platform.h>
#include <SDL_syswm.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

namespace {
bool allowed(NSScreen* screen)
{
    if (!screen) return false;
    const CGDirectDisplayID id = [[screen.deviceDescription objectForKey:@"NSScreenNumber"] unsignedIntValue];
    return CGDisplayIsBuiltin(id) && CGDisplayIsActive(id) &&
           !CGDisplayIsInMirrorSet(id);
}
}

bool BuiltinDisplayGuard::enabled()
{
    static const bool value = qEnvironmentVariableIntValue("MOONLIGHT_BUILTIN_DISPLAY_ONLY") == 1;
    return value;
}

QScreen* BuiltinDisplayGuard::screen()
{
    for (QScreen* screen : QGuiApplication::screens()) {
        auto* native = screen->nativeInterface<QNativeInterface::QCocoaScreen>();
        if (native && allowed(native->nativeScreen())) return screen;
    }
    return nullptr;
}

bool BuiltinDisplayGuard::allows(SDL_Window* window)
{
    if (!enabled()) return true;
    SDL_SysWMinfo info{};
    SDL_VERSION(&info.version);
    return window && SDL_GetWindowWMInfo(window, &info) &&
           info.subsystem == SDL_SYSWM_COCOA && allowed(info.info.cocoa.window.screen);
}

void BuiltinDisplayGuard::watch(QWindow* window)
{
    if (!enabled()) return;
    auto check = [window] {
        QScreen* builtin = screen();
        if (!builtin || window->screen() != builtin) {
            window->hide();
            qCritical() << "Built-in display guard: display unavailable, mirrored, or window moved to external display. Closing client.";
            QCoreApplication::exit(2);
        }
    };
    QObject::connect(window, &QWindow::screenChanged, window, check);
    // Also catches clamshell and mirroring changes without a screenChanged signal.
    auto* timer = new QTimer(window);
    QObject::connect(timer, &QTimer::timeout, window, check);
    timer->start(500);
    check();
}
