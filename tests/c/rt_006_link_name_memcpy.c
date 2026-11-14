// RT-6: the program's own copy routine, which vole names `memcpy` and
// links by #[link_name]: it copies the bytes in reverse order.
#include <stddef.h>

void *rt006_rev_copy(void *d, const void *s, size_t n) {
    unsigned char *a = d;
    const unsigned char *b = s;
    for (size_t i = 0; i < n; i++) {
        a[i] = b[n - 1 - i];
    }
    return d;
}

// RT-6's second case: the program's own two-argument function, which vole
// names `fmod`.
double rt006_not_fmod(double a, double b) {
    (void)a;
    (void)b;
    return 42.0;
}
