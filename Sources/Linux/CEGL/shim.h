#include <EGL/egl.h>
#include <EGL/eglext.h>

// eglGetPlatformDisplayEXT is an extension entry point: fetched at run time.
static inline EGLDisplay cegl_surfaceless_display(void) {
    PFNEGLGETPLATFORMDISPLAYEXTPROC get = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
    return get ? get(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, (const EGLint *)0) : EGL_NO_DISPLAY;
}
