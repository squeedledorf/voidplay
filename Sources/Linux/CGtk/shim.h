#include <gtk/gtk.h>
#include <pango/pangocairo.h>

// Function-like macros Swift cannot import.
static inline gulong cgtk_signal_connect(gpointer instance, const gchar *signal, GCallback handler, gpointer data) {
    return g_signal_connect_data(instance, signal, handler, data, NULL, 0);
}
static inline GtkWidget *cgtk_widget(gpointer p) { return GTK_WIDGET(p); }
static inline GtkWindow *cgtk_window(gpointer p) { return GTK_WINDOW(p); }
static inline GtkDrawingArea *cgtk_drawing_area(gpointer p) { return GTK_DRAWING_AREA(p); }
static inline GtkEventController *cgtk_event_controller(gpointer p) { return GTK_EVENT_CONTROLLER(p); }
static inline GtkGesture *cgtk_gesture(gpointer p) { return GTK_GESTURE(p); }
static inline GtkGestureSingle *cgtk_gesture_single(gpointer p) { return GTK_GESTURE_SINGLE(p); }
