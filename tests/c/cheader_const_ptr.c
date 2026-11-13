/* The C side of tests/run/cheader_const_ptr.vl, through the header volec
   --emit-header makes for it: each prototype is declared again as the
   header must have it (a `*const T` is `const T *`), which the C compiler
   refuses when the two differ. */
#include <stdio.h>
#include "constptr_out.h"

int64_t total(const int64_t *xs, int64_t n);
void poke(int64_t *p, int64_t v);
const uint8_t *nth(const uint8_t *const *names, int64_t i);
const void *same(const void *p);

int c_drive(void) {
    int64_t xs[3] = {1, 2, 3};
    poke(&xs[1], 40);
    const uint8_t *names[2] = {(const uint8_t *)"zero", (const uint8_t *)"one"};
    printf("%lld %s %d\n", (long long)total(xs, 3), (const char *)nth(names, 1),
        same(xs) == (const void *)xs);
    return 0;
}
