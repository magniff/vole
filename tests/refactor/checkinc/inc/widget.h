/* A header found only through -I inc (tests/refactor/checkinc.t). */
#define WIDGET_MAX 8
struct widget { int id; int size; };
int widget_count(const struct widget *w, int n);
