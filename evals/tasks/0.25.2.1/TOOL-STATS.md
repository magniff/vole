| project | tool calls | Bash | Edit | Write | Read | volec calls (by subcommand) | hook blocks | failed tool calls |
|---|---|---|---|---|---|---|---|---|
| qwen35 | 112 | 100 | 0 | 4 | 1 | build 24, query items 15, guide 10, query show 10, check 8, test 4, query context 1 | 1 (query-first 1) | 9 |
| ocean | 58 | 49 | 1 | 0 | 7 | build 18, check 14, query items 12, guide 9, query show 9, test 7, query text 4, query context 3 | 1 (query-first 1) | 4 |
| sph | 38 | 29 | 0 | 5 | 4 | guide 6, build 6, test 5, check 2 | 1 (query-first 1) | 2 |
| physarum | 50 | 32 | 6 | 6 | 6 | query show 12, build 7, guide 4, check 3, query items 1, test 1 | 1 (query-first 1) | 4 |
| cloth | 55 | 46 | 0 | 5 | 4 | query show 13, build 12, fmt 9, check 6, test 6, guide 4, query items 1 | 0 () | 1 |
| mandelbulb | 31 | 17 | 5 | 5 | 4 | guide 10, query items 8, query show 6, build 4, test 3 | 0 () | 1 |
| deferred | 49 | 43 | 0 | 0 | 5 | check 13, build 11, guide 9, query show 9, test 7, fix 5, query items 3 | 1 (query-first 1) | 3 |
| terrain | 62 | 47 | 0 | 7 | 8 | query items 19, build 15, guide 12, query show 8, test 7, check 4, query context 1, query refs 1 | 0 () | 1 |
| sdftext | 51 | 33 | 5 | 9 | 4 | query show 14, query items 8, build 7, guide 6, check 3, test 3, query context 1 | 0 () | 1 |
| windtunnel | 80 | 51 | 21 | 4 | 4 | build 14, check 9, guide 7, test 4, edit 1, move 1 | 0 () | 3 |
