/* The header of tests/lsp/cimport.lsp, found through -I inc. */
#ifndef WIDGET_H
#define WIDGET_H

#define WIDGET_MAX 8

struct widget {
    int id;
    int size;
};

/* How many of the n widgets at w have a size. */
int widget_count(const struct widget *w,
                 int n);

#endif
