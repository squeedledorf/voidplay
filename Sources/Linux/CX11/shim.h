#include <gtk/gtk.h>
#include <gdk/x11/gdkx.h>

static inline int cx11_is_x11_display(GdkDisplay *d) { return GDK_IS_X11_DISPLAY(d); }
