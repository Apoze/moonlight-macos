#pragma once

class QScreen;
class QWindow;
struct SDL_Window;

// Opt-in guard for the first macOS development phase. No display modes change.
namespace BuiltinDisplayGuard {
bool enabled();
QScreen* screen();
bool allows(SDL_Window* window);
void watch(QWindow* window);
}
