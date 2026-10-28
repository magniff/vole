| project | tool calls | Bash | Edit | Write | Read | volec calls (by subcommand) | hook blocks | failed tool calls |
|---|---|---|---|---|---|---|---|---|
| qwen35 | 179 | 99 | 63 | 12 | 5 | query items 18, build 18, check 14, guide 11, query context 8, query grep 7, query show 5, test 4 | 11 (query-first 9, edit-tool 2) | 17 |
| ocean | 75 | 33 | 27 | 6 | 9 | guide 9, query show 8, build 6, fix 3, check 3, try 3, query grep 2, query items 2 | 4 (query-first 2, edit-tool 2) | 6 |
| sph | 68 | 35 | 22 | 6 | 5 | query text 9, build 8, guide 7, query items 7, query grep 4, query show 4, test 2, query context 1 | 4 (query-first 3, edit-tool 1) | 6 |
| physarum | 58 | 28 | 14 | 6 | 10 | guide 9, build 8, test 2, query grep 1, query context 1, query show 1, check 1 | 3 (query-first 2, edit-tool 1) | 5 |
| cloth | 102 | 62 | 31 | 6 | 3 | query show 27, build 18, query items 10, guide 6, query grep 6, test 4, query refs 3, query context 2 | 9 (query-first 7, edit-tool 2) | 12 |
| mandelbulb | 71 | 41 | 22 | 0 | 8 | query items 13, test 9, guide 8, query show 8, query context 7, check 5, build 4, query grep 3 | 4 (query-first 4) | 6 |
| deferred | 74 | 39 | 25 | 0 | 10 | query items 25, query show 18, query grep 8, check 7, build 7, guide 6, test 6, fix 4 | 4 (query-first 3, edit-tool 1) | 6 |
| terrain | 67 | 39 | 13 | 6 | 9 | query show 18, query items 15, guide 7, build 7, check 5, query refs 3, edit 3, query text 3 | 5 (query-first 4, edit-tool 1) | 7 |
| sdftext | 68 | 37 | 19 | 9 | 3 | query show 15, guide 11, query grep 10, check 9, query items 6, test 5, fix 3, build 2 | 3 (edit-tool 2, query-first 1) | 4 |
| windtunnel | 87 | 46 | 25 | 6 | 10 | build 10, guide 5, query items 4, check 4, test 3, query show 1, query refs 1, fix 1 | 6 (query-first 5, edit-tool 1) | 10 |
