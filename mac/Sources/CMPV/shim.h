// Absolute paths into the Homebrew prefix: this machine has no pkg-config, so the
// module map cannot resolve <mpv/client.h> from a search path. If mpv moves, this
// is the single place to change.
#include "/usr/local/opt/mpv/include/mpv/client.h"
#include "/usr/local/opt/mpv/include/mpv/render.h"
#include "/usr/local/opt/mpv/include/mpv/render_gl.h"
