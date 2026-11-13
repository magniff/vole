/* The C side of tests/run/cimport_const_ptr.vl. */
#include "constptr.h"

long sum_const(const long *xs, long n) {
    long t = 0;
    for (long i = 0; i < n; i++) t += xs[i];
    return t;
}

void fill(long *xs, long n, long v) {
    for (long i = 0; i < n; i++) xs[i] = v;
}

const char *pick(const char *const *names, int i) { return names[i]; }

unsigned long cstr_len(const char s[]) {
    unsigned long n = 0;
    while (s[n]) n++;
    return n;
}

long span_copy(const struct span *s) {
    for (long i = 0; i < s->n; i++) s->out[i] = s->data[i];
    return s->n;
}
