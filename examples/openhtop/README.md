# openhtop

A process monitor in the terminal, after htop. The header is two panels:
CPU, memory and swap meters on the left, and the task count, load average
and uptime on the right, with every CPU's own bar and load underneath.
Below it is a table of the processes with their user, priority, sizes,
state, CPU and memory shares and CPU time, then a status line for the
selection and a function key bar. It reads the system, it does not
simulate it, and it can sort, filter, scroll and kill.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o openhtop && ./openhtop
```

`main.vl` is the root of a module tree; the compiler loads the files next
to it (`model.vl`, `ui.vl`, and the rest). It needs a terminal; without one
it prints a single frame and exits, as with `--once`. `--demo` shows a
fixed snapshot, which is what the test case uses:

```sh
./openhtop --demo --once --width 100 --height 16
```

The keys:

| key | what it does |
|---|---|
| `q`, `F10`, `Esc`, Ctrl-C | quit |
| `j`/`k`, arrows | next and previous process |
| `PgUp`/`PgDn`, `Home`/`End` | a page, the first, the last |
| `s`, `F3` | sort by CPU, memory, PID, CPU time or command |
| `r`, `F4` | reverse the order |
| `/`, `F2` | filter by command or user (Enter or Esc ends) |
| `x`, `F9` | send `SIGTERM` to the selected process (`y` confirms) |
| `p`, `F5` | pause the refreshes |
| `?`, `F1` | help; any key closes it |

The options: `--demo`, `--once`, `--no-color`, `-d/--delay MS`,
`-s/--sort FIELD`, `--width COLUMNS`, `--height ROWS`, `--pid PID` and
`--filter TEXT`.

## Expected output

The fixed snapshot, at 100 columns and 16 rows:

```text
 CPU [|||||||        37.4%]                       Tasks:    7, 24 thr, 2 running
 Mem [||||||||  6.5G/16.0G]                       Load avg: 1.24 0.98 0.76
 Swp [|||      320.0M/2.0G]                       Uptime:   03:25:45
Cores  1[|    12.0%]  2[|||| 48.0%]  3[|     3.0%]  4[|||| 91.0%]  5[||   22.0%]  6[      0.0%]
       7[|||| 64.0%]  8[|||| 57.0%]
   PID USER      PRI   NI    VIRT     RES    SHR  S   CPU%   MEM%     TIME+ Command
  1812 ada        31    0    3.0G    1.4G  96.0M  R  180.0    8.7      2:00 volec test
   704 ada        31    0    2.0G  812.0M  64.0M  S   72.4    5.0      0:48 postgres: writer
  2600 ada        31    0    1.5G  512.0M  24.0M  S   31.2    3.1      0:54 cargo build
  2400 ada        31    0  256.0M    9.0M   4.0M  R   12.0    0.1      0:03 openhtop
   322 root       31    0  425.0M    8.0M   3.1M  S    2.1    0.0      0:00 logd
     1 root       31    0    4.2G   18.0M  11.7M  S    1.5    0.1      0:00 launchd
  3001 root       31    0  128.0M    7.2M   2.0M  S    0.0    0.0      0:00 sshd: ada

 PID 1812  User ada  Command volec test  Sort CPU v
 F1 Help  F2 Filter  F3 Sort  F4 Reverse  F5 Pause  F9 Kill  F10 Quit
```

On a terminal colors and a highlighted selection appear: green, yellow
and red by load in the meters, the per-CPU bars and the CPU column, the
running processes in green, the selection as a cyan band, the column
headings as a cyan bar with the sort column highlighted, and the function
keys as green chips. `--no-color`, `--once` on a pipe and a non-terminal
stdout leave the escape sequences out, so the output stays plain text.

Under 90 columns the table drops the priority and sizes; under 60 it drops
the user and the CPU time, and the header becomes two compact lines of
percentages. The per-CPU bars stay in every width and wrap onto as many
lines as they need, so every CPU and its load is always listed. A CPU
whose counters could not be read still gets its bar, with `--%` in place
of the load.

## The source

The program is split by what each file knows:

| file | what it holds |
|---|---|
| `main.vl` | the program's overview, the modules, the command line, `main` |
| `model.vl` | `Proc`, `Snapshot`, `State`, `Key`, and filtering, sorting and selection |
| `text.vl` | byte and text helpers for the lines the backends read |
| `platform.vl` | the C calls (Mach's found at run time), command output, the terminal's size and raw keys |
| `linux.vl` | a snapshot from `/proc` |
| `macos.vl` | a snapshot from `ps`, `vm_stat`, `sysctl` and Mach |
| `snapshot.vl` | the backend choice, and the difference between two snapshots |
| `demo.vl` | the fixed snapshot for `--demo` and the test |
| `format.vl` | sizes, times, bars and colors |
| `ui.vl` | the frame: header, meters, table, status and key bar |
| `app.vl` | `--once` and the interactive loop |

## How it works

**A snapshot, then the difference of two.** One `Snapshot` holds the
processes, the memory and swap totals, the load average, the uptime and
the raw CPU counters, per CPU. A process's CPU share is not in any of
those files: it is the growth of its CPU time between two snapshots
divided by the wall time between them. The same for a CPU's share, from
the growth of its busy and idle ticks: the idle time in `/proc/stat`
(Linux), or the four tick counters of `host_processor_info` (macOS). The
machine's share is the busy time over every core, or on macOS the sum of
the processes' shares over the cores. So `--once` takes two samples
150 ms apart, and the interface keeps the previous snapshot and refreshes
every `--delay` milliseconds.

**Two backends, one binary.** On Linux the data comes from `/proc`: `stat`
(state, parent, times, priority, threads, sizes), `statm` (shared pages),
`status` (the uid), `cmdline` (the command), plus `meminfo`, `uptime` and
`loadavg`. On macOS it comes from `ps -axo ...` for the processes,
`vm_stat` for the memory in use, and `sysctl` for the memory size, the
page size, the swap and the boot time; the per-CPU tick counters are
Mach's `host_processor_info`, which also gives the core count. The program
picks the backend at run time by asking whether `/proc/self/stat` exists,
so the same source builds and links on both systems: everything on the
macOS side is an ordinary command (`std::process::Command`), a portable
libc call (`getloadavg`, `getpagesize`, `ioctl`), or a Mach function
looked up with `dlsym`. Linux has no `host_processor_info`, so the lookup
returns null there and `/proc/stat` answers instead; the binary itself
links on both.

On macOS `ps` does not report a useful virtual size (its `vsz` is the same
reservation for every process) or a shared size, so VIRT and SHR are 0
there. A process new since the previous snapshot shows 0% until the next
one.

**The terminal.** `std::sys` puts the terminal in raw mode (`sys_make_raw`,
`sys_tcsetattr`), the alternate screen (`\x1b[?1049h`) is opened, the
cursor hidden, and all three restored with a `defer`, including on the
early return paths. Keys are read with `poll` and `read`; the escape
sequences of the arrows, PgUp/PgDn, Home/End and F1 to F12 (both the CSI
`\x1b[15~` and the SS3 `\x1bOP` forms) are decoded by hand. The window
size is `ioctl(TIOCGWINSZ)` on a `#[repr(C)]` `struct winsize`; `--width`
and `--height` override it for tests. Raw mode turns off output
post-processing, so a line ends with `\r\n`: without the carriage return
every row would start in the last column and wrap to a blank line.

**A frame in one `Buf`.** Each line is a `Line`: a `Buf`, the visible
columns used so far (escape sequences do not count), the line's width, and
an optional base style. Padding, right and left alignment and cutting
(never inside a UTF-8 character) all go through `Line`, so the columns
line up and nothing overflows; a base style lets a colored cell sit on a
selected row's cyan band and return to it. The whole frame is built, then
written with one `write` at the home position; the last line's newline is
left out so a full screen does not scroll. In `--once` mode the carriage
returns and the padding at the end of each line are dropped, so the output
is plain LF-terminated text a test can compare.

**The list.** `process_matches` applies `--pid` and the filter (ASCII
case-folded, over the command and the user); `sort_processes` sorts the
snapshot by the chosen field with `sort_by`; `clamp_offset` keeps the
selected pid inside the window and the window inside the list. The
selection is a pid, not a row, so a refresh that reorders the list does
not change what is selected.

## Language features

- modules, `pub`, `use` and a module tree: `volec guide modules`
- `fn main(gpa: Gpa)`, `Vec`/`Buf` on an allocator, f-strings and
  `format_in`: `volec guide allocators`, `volec guide formatting`
- `inout` parameters and `&x` at the call, `sink`, `defer`:
  `volec guide memory`
- `extern "C"` (`getloadavg`, `getpagesize`, `ioctl`), `#[repr(C)]`,
  `unsafe`: `volec guide c-interop`
- `std::sys` (`poll`, `read`, `write`, raw mode, `ioctl` numbers),
  `std::process::Command`, `std::cli`: `volec guide std`, `volec guide cli`
- slices, `[u8; N]` arrays in a copied struct, `sort_by`:
  `volec guide types`, `volec guide std`
