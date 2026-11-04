/* (0.26.4) The preprocessor's arithmetic is on 64-bit words, and wraps:
   tests/run/cimport_cpp_wrap.vl. */
#if (-9223372036854775807 - 1) / -1 < 0
#define DIV_MIN 1
#else
#define DIV_MIN 2
#endif
#if 0u - 1 > 0
#define SUB_WRAP 3
#else
#define SUB_WRAP 4
#endif
#if 4294967296 * 4294967296 == 0
#define MUL_WRAP 5
#else
#define MUL_WRAP 6
#endif
