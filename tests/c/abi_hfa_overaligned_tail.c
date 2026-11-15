// (0.30.1) Over-aligned float aggregates and the stack: one with tail
// padding is no HFA and goes by reference; one without (D2A16) goes on
// the stack at its element's alignment, after the f32 before it.
typedef struct __attribute__((aligned(32))) { float a, b, c; } F3A32;
typedef struct __attribute__((aligned(16))) { double a, b; } D2A16;

long c_tail(double r0, double r1, double r2, double r3, double r4, double r5, double r6,
            double r7, F3A32 p, float y, D2A16 q, int k) {
    return (long)(p.a * 100000 + p.b * 10000 + p.c * 1000 + y * 100 + q.a * 10 + q.b) + k * 1000000;
}

long v_tail(double r0, double r1, double r2, double r3, double r4, double r5, double r6,
            double r7, F3A32 p, float y, D2A16 q, int k);

long c_call_tail(void) {
    F3A32 p = {1, 2, 3};
    D2A16 q = {5, 6};
    return v_tail(0, 0, 0, 0, 0, 0, 0, 0, p, 4.0f, q, 7);
}
