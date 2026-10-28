#include "widget.h"

/* { not a body } */
int widget_count(const struct widget *w, int n)
{
    int k = 0;
    for (int i = 0; i < n; i++) {
        if (w[i].size > 0) {
            k++;
        }
    }
    return k;
}
