// RT-CG-1: over-aligned homogeneous float aggregates passed on the stack (Apple AArch64).
typedef struct __attribute__((aligned(16))) { double a, b, c, d; } D4A16;
typedef struct __attribute__((aligned(32))) { double a, b, c, d; } D4A32;
typedef struct { float a[3]; } F3;

// the argument's fields as one number: a*1000 + b*100 + c*10 + d
long c_take16(double r0, double r1, double r2, double r3, double r4, double r5, double r6, double r7,
              float x, D4A16 p) {
    return (long)(x * 10000 + p.a * 1000 + p.b * 100 + p.c * 10 + p.d);
}
long c_take32(F3 a, F3 b, F3 c, D4A32 p) {
    return (long)(c.a[0] * 10000 + p.a * 1000 + p.b * 100 + p.c * 10 + p.d);
}

long v_take16(double r0, double r1, double r2, double r3, double r4, double r5, double r6, double r7,
              float x, D4A16 p);
long v_take32(F3 a, F3 b, F3 c, D4A32 p);

long c_call16(void) {
    D4A16 p = {1, 2, 3, 4};
    return v_take16(0, 0, 0, 0, 0, 0, 0, 0, 9.0f, p);
}
long c_call32(void) {
    F3 f = {{9, 0, 0}};
    D4A32 p = {1, 2, 3, 4};
    return v_take32(f, f, f, p);
}
