/* tests/main_stack.sh: a planted failure of the compiler's own thread.
   Interposed on pthread_attr_setstacksize and pthread_create (macOS
   DYLD_INSERT_LIBRARIES): SHIM_MODE=nosize refuses every stack size,
   nobig refuses to create a thread whose stack is 1 GiB or more;
   childnobig refuses it only in a volec another volec started
   (VOLEC_NESTED, set after the first volec made its own thread), and
   eagernobig only in a lazy std's build made again (VOLE_STD_EAGER). */
#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

#define INTERPOSE(rep, orig) \
    __attribute__((used)) static struct { const void *r; const void *o; } \
    interpose_##orig __attribute__((section("__DATA,__interpose"))) = \
        { (const void *)(unsigned long)&rep, (const void *)(unsigned long)&orig };

static int shim_create(pthread_t *t, const pthread_attr_t *a, void *(*f)(void *), void *arg) {
    size_t size = 0;
    const char *m = getenv("SHIM_MODE");
    if (a) pthread_attr_getstacksize(a, &size);
    int big = size >= ((size_t)1 << 30);
    if (m && !strcmp(m, "nobig") && big) return EAGAIN;
    if (m && !strcmp(m, "childnobig") && big && getenv("VOLEC_NESTED")) return EAGAIN;
    if (m && !strcmp(m, "eagernobig") && big && getenv("VOLE_STD_EAGER")) return EAGAIN;
    return pthread_create(t, a, f, arg);
}

static int shim_setstacksize(pthread_attr_t *a, size_t size) {
    const char *m = getenv("SHIM_MODE");
    if (m && !strcmp(m, "nosize")) return EINVAL;
    return pthread_attr_setstacksize(a, size);
}

INTERPOSE(shim_create, pthread_create)
INTERPOSE(shim_setstacksize, pthread_attr_setstacksize)
