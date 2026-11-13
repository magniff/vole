/* tests/run/cimport_const_ptr.vl: C's `const T *` is imported as
   `*const T`, `T *` as `*mut T` (0.29). */
long sum_const(const long *xs, long n);
void fill(long *xs, long n, long v);
const char *pick(const char *const *names, int i);
unsigned long cstr_len(const char s[]);
struct span { const unsigned char *data; unsigned char *out; long n; };
long span_copy(const struct span *s);
