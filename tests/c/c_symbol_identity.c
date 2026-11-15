// 0.30.1: the program's own functions, which its vole code declares under
// the names of C's (malloc, calloc, free, exit, sin, sqrt): a C function
// is the symbol it links to, never the name vole calls it, so each call
// here is made at every level (tests/run/c_symbol_*.vl).
#include <stdlib.h>
#include <string.h>

static long allocs = 0, frees = 0, exits = 0, sines = 0;

void *csi_alloc(size_t n) { allocs++; return malloc(n); }
void *csi_calloc(size_t n, size_t m) { allocs++; return calloc(n, m); }
void csi_free(void *p) { frees++; free(p); }
long csi_allocs(void) { return allocs; }
long csi_frees(void) { return frees; }

// Returns, unlike C's exit.
void csi_exit(int code) { (void)code; exits++; }
long csi_exits(void) { return exits; }

// Counts its calls, unlike C's sin (which writes no memory).
double csi_sin(double x) { sines++; return x; }
long csi_sines(void) { return sines; }

// Not C's sqrt.
double csi_sqrt(double x) { (void)x; return 42.0; }

// A C static the program names otherwise (0.30.1: its symbol is the
// #[link_name], as a function's).
long csi_counter = 5;
long csi_counter_now(void) { return csi_counter; }
