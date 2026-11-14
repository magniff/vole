#!/bin/sh
# Makes bulk/: a program of N modules that each import and call
# lib::old_fn, for the rewrite that needs a new import in every one.
# usage: sh gen_bulk.sh N
n=$1
mkdir bulk
{
    echo "mod lib;"
    echo "mod lib2;"
    i=1
    while [ "$i" -le "$n" ]; do echo "mod m$i;"; i=$((i + 1)); done
    echo
    echo "fn main() -> i32 {"
    echo "    let mut s: i64 = 0;"
    i=1
    while [ "$i" -le "$n" ]; do echo "    s += crate::m$i::f();"; i=$((i + 1)); done
    echo "    (s % 100) as i32"
    echo "}"
} > bulk/main.vl
printf 'pub fn old_fn(x: i64) -> i64 {\n    x + 1\n}\n' > bulk/lib.vl
printf 'pub fn new_fn(x: i64) -> i64 {\n    x + 1\n}\n' > bulk/lib2.vl
i=1
while [ "$i" -le "$n" ]; do
    printf 'use crate::lib::old_fn;\n\npub fn f() -> i64 {\n    old_fn(%s)\n}\n' "$i" > "bulk/m$i.vl"
    i=$((i + 1))
done
