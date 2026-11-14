## 0.30: `query unsafe --source` and `edit justify` (the 0.29 tool
## diaries: 119 comments went through two scripts and eight
## regenerations of the listing, whose lines moved with every insertion).
## --source: each site's lines under it (at most 12); --json has end_line.
$ query unsafe --unjustified --source
main.vl:2	block	crate::read	raw-pointer	missing both	deref
    2	    unsafe { *p }
main.vl:6	block	crate::twice	raw-pointer	missing both	deref
    6	    let a = unsafe { *p };
main.vl:8	block	crate::twice	raw-pointer	missing SAFETY:	deref
    8	    let b = unsafe { *p };
main.vl:10	block	crate::twice	raw-pointer	missing both	deref
    10	        unsafe { *p };
main.vl:17	block	crate::pick	raw-pointer	missing both	deref
    17	    } else if unsafe { *p } > 0 {
main.vl:26	block	crate::sum	raw-pointer	missing both	deref, unsafe-call(*const i64::add)
    26	    unsafe {
    27	        for i in 0..n {
    28	            total += *p.add(i);
    29	        }
    30	    }
sites: 6 (6 blocks, 0 unsafe fns, 0 extern blocks); unjustified: 6; unneeded: 0
$ query unsafe --json main.vl | cut -c1-74
{"file":"main.vl","line":2,"end_line":2,"kind":"block","item":"crate::read
{"file":"main.vl","line":6,"end_line":6,"kind":"block","item":"crate::twic
{"file":"main.vl","line":8,"end_line":8,"kind":"block","item":"crate::twic
{"file":"main.vl","line":10,"end_line":10,"kind":"block","item":"crate::tw
{"file":"main.vl","line":17,"end_line":17,"kind":"block","item":"crate::pi
{"file":"main.vl","line":26,"end_line":30,"kind":"block","item":"crate::su
## One site: the comments above its line, indented like it.
$ edit justify main.vl:2 --unsafe 'the pointer is the caller'"'"'s, raw' --safety 'every caller passes the address of a live i64' --show
justified 1 site	main.vl	+2 -0 lines
// main.vl:2-3
2	    // UNSAFE: the pointer is the caller's, raw
3	    // SAFETY: every caller passes the address of a live i64
% git checkout -q .
## A list: a site a line, FILE:LINE<TAB>UNSAFE TEXT<TAB>SAFETY TEXT, the
## lines those of one `query unsafe` run (the file before the edit); an
## empty text for a comment the site has; \n for a second line.
% cat $T/inputs/justify-list.txt
main.vl:2	the pointer is the caller's, raw	every caller passes the address of a live i64
main.vl:8		p is the address of a live i64 (main)
# the third: a comment of two lines
main.vl:10	a raw pointer is read	p is the address of a live i64:\nmain passes &x
$ edit justify --from $T/inputs/justify-list.txt --show
justified 3 sites	main.vl	+6 -0 lines
// main.vl:2-3
2	    // UNSAFE: the pointer is the caller's, raw
3	    // SAFETY: every caller passes the address of a live i64
// main.vl:10
10	    // SAFETY: p is the address of a live i64 (main)
// main.vl:13-15
13	        // UNSAFE: a raw pointer is read
14	        // SAFETY: p is the address of a live i64:
15	        // main passes &x
$ query unsafe --unjustified
main.vl:8	block	crate::twice	raw-pointer	missing both	deref
main.vl:23	block	crate::pick	raw-pointer	missing both	deref
main.vl:32	block	crate::sum	raw-pointer	missing both	deref, unsafe-call(*const i64::add)
sites: 3 (3 blocks, 0 unsafe fns, 0 extern blocks); unjustified: 3; unneeded: 0
% git checkout -q .
## A long text is wrapped at 100 columns.
$ edit justify main.vl:26 --unsafe 'the elements are read through a raw pointer and an offset, which no slice of the caller covers here' --safety 'the caller passes the address of n live elements, so every p.add(i) with i < n is inside them and initialized' --show
justified 1 site	main.vl	+4 -0 lines
// main.vl:26-29
26	    // UNSAFE: the elements are read through a raw pointer and an offset, which no slice of the
27	    // caller covers here
28	    // SAFETY: the caller passes the address of n live elements, so every p.add(i) with i < n is
29	    // inside them and initialized
% git checkout -q .
## What cannot be justified so is named, and nothing is written: no site
## on the line; a comment the site still lacks; a site whose statement
## starts on a line that ends another (the audit would not count a
## comment above it).
$ edit justify main.vl:3 --unsafe a --safety b main.vl:6 --unsafe a main.vl:17 --unsafe a --safety b main.vl:2 --unsafe a --safety b
error edit.justify: site 1 (main.vl:3): no unsafe block, unsafe fn or extern block starts on that line; the nearest site is on line 2 (volec query unsafe FILE lists them)
error edit.justify: site 2 (main.vl:6) has no // SAFETY: comment and none was given (--safety TEXT)
error edit.justify: site 3 (main.vl:17): a comment above that line would not be counted (the site's statement starts on a line that ends another, `} else ...`): write it by hand, inside the statement or at the end of the site's line
error edit.justify: 3 of 4 sites left as they are; nothing written (--keep-going writes the other 1)
[exit 1]
% git status --short
$ edit justify main.vl:3 --unsafe a --safety b main.vl:2 --unsafe a --safety b --keep-going
justified 1 site of 2	main.vl	+2 -0 lines
error edit.justify: site 1 (main.vl:3): no unsafe block, unsafe fn or extern block starts on that line; the nearest site is on line 2 (volec query unsafe FILE lists them)
warning edit.justify: 1 of 2 sites left as they are; 1 written
[exit 1]
% git checkout -q .
## Usage.
$ edit justify --unsafe a --safety b
error edit.usage: the site, FILE:LINE, comes before its --unsafe and --safety
try: volec edit justify FILE:LINE --unsafe TEXT --safety TEXT
[exit 2]
$ edit justify main.vl:2
error edit.usage: a site needs its --unsafe TEXT, its --safety TEXT or both
try: volec edit justify FILE:LINE --unsafe TEXT --safety TEXT
[exit 2]
$ edit justify main.vl --unsafe a
error edit.usage: the site, FILE:LINE, comes before its --unsafe and --safety
try: volec edit justify FILE:LINE --unsafe TEXT --safety TEXT
[exit 2]
