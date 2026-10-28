# nes

An NES emulator: a 6502, a 2C02 picture unit, the APU's frame counter,
two controllers, and the cartridge mappers most games used. It plays
`.nes` files in a window at the console's 60.0988 Hz, or headless for
tests, and it is written in vole alone — `std::gpu` for the window,
everything else from the compiler's own `std`.

```sh
target/volec -O2 examples/nes/main.vl -o nes
./nes game.nes                  # a window
./nes game.nes --scale 3        # three screen pixels per NES pixel
./nes --check                   # the built-in checks, no ROM needed
./nes game.nes --headless --frames 600 --shot frame.ppm
./nes game.nes --info           # the header: mapper, sizes, mirroring
```

The picture is the console's 256×240 frame buffer, uploaded to the GPU
as a storage buffer and drawn by a fullscreen shader with
nearest-neighbour sampling at an integer scale (`--scale 0`, the
default, picks the largest that fits the window). The frame clock is
fixed at 60.0988 Hz; `Tab` runs four times faster.

| keys | player 1 | player 2 |
|---|---|---|
| d-pad | arrows | I / J / K / L |
| A | X | O |
| B | Z | U |
| start | Enter | P |
| select | Right Shift | Y |

| key | action |
|---|---|
| F1 | reset |
| F2 | pause |
| Tab | fast-forward while held |
| F11 | fullscreen |
| Esc | quit |

## The mappers

The header decides; a cartridge whose mapper is not on this list is
refused with its number and the list, never run half-understood.

| # | board | used by |
|---|---|---|
| 0 | NROM | the launch titles, most homebrew |
| 1 | MMC1 (SxROM) | *The Legend of Zelda*, *Metroid*, *Mega Man 2* |
| 2 | UxROM | *Mega Man*, *Contra*, *Castlevania* |
| 3 | CNROM | *Gradius*, *Arkanoid* |
| 4 | MMC3 (TxROM) | *Super Mario Bros. 3*, *Kirby's Adventure*, *Mega Man 3–6* |
| 7 | AxROM | *Battletoads*, *Marble Madness* |
| 11 | Color Dreams | the unlicensed Color Dreams/Wisdom Tree games |
| 66 | GxROM | *Super Mario Bros.* + *Duck Hunt* |

iNES and NES 2.0 headers are both read; CHR RAM (the `CHR = 0` boards)
works, as do horizontal, vertical, one-screen and four-screen
nametable mirroring, battery-backed PRG RAM (kept for the session, not
written to disk), and the MMC3 scanline IRQ for split screens.

## The files

| file | what |
|---|---|
| `main.vl` | arguments, the window loop, the headless runner, the PPM writer, `--check` |
| `nes.vl` | the machine: reset, `run_frame`, the CPU/PPU/APU accounting |
| `bus.vl` | the 64 KiB address space: RAM, PPU registers, APU, pads, cartridge, DMA |
| `cpu.vl` | the 6502: every official and unofficial opcode, cycle counts, NMI/IRQ/BRK |
| `ppu.vl` | the 2C02: registers, `v`/`t` scrolling, the line renderer, vblank/NMI, sprite 0 |
| `apu.vl` | the register surface, the frame sequencer, the four length counters, frame IRQ |
| `cart.vl` | the mappers: PRG/CHR windows, MMC1's serial port, MMC3's A12 counter |
| `rom.vl` | the iNES/NES 2.0 parser and its error messages |
| `pad.vl` | one standard controller: strobe and shift register |
| `view.vl` | the WGSL shader and the integer-scaled fullscreen pass |
| `check.vl` | the built-in checks (`--check`), on synthetic cartridges |

## Time

The CPU is instruction-at-a-time and the PPU is stepped in dots: every
bus access runs the PPU three dots (one CPU cycle) *before* it lands,
and the cycles an instruction spends without a bus access are ticked at
its end. That gives one-CPU-cycle resolution for free — NMI and IRQ
are taken at instruction boundaries just as on the console — without
the bookkeeping of a cycle-stepped core.

The PPU renders a line at dot 0 from the current `v`/`t` and `$2001`,
the way a scanline renderer does, so a mid-line `$2005`/`$2006` change
lands on the next line rather than partway through one. That is enough
for status bars, scrolling and most split screens (MMC3's IRQ fires on
the right line, at dot 263 or 327 depending on which pattern table the
sprite fetches use); it is not enough for effects that change the
scroll within a line — the raster tricks a few demos use — and it is
not a cycle-accurate 2C02.

## What is checked

`tests/run.sh nes` runs `nes --check`, which needs no ROM and no
window: a synthetic cartridge is assembled in memory for each check and
the machine runs it. The 21 checks cover the parser (a good header, a
header with CHR RAM, and the five ways a file is refused), every
mapper's bank windows (NROM's
mirroring, UxROM's fixed last bank, CNROM's CHR bank, MMC1's serial
register in PRG modes 2 and 3, MMC3's PRG/CHR modes and its A12 IRQ),
a summing loop on the CPU, the PPU's palette, nametable, background,
sprite-0 hit and vblank/NMI, the APU's length counter and frame IRQ,
and a painted cartridge end to end.

The emulator itself is checked against the standard test ROMs (none of
which are in this repository):

| suite | result |
|---|---|
| `nestest` (CPU, 8991 instructions) | every line matches the reference log: PC, opcode, A, X, Y, P, SP |
| `instr_test-v5` (`all_instrs`, `official_only`) | "All 16 tests passed" |
| `instr_timing` | Passed |
| `branch_timing` | Passed |
| `cpu_interrupts_v2` `1-cli_latency` | Passed |
| `ppu_vbl_nmi` 01–10 | Passed |
| `mmc3_test_2` 1–5 | Passed (6 is the other chip revision; see below) |
| `sprite_hit_tests` 01–07 | "PASSED" |
| `sprite_overflow_tests` 5 (Emulator) | Passed; 1–4 need the overflow bug (see below) |

## The limits

- **Sound is not synthesised.** `std` has no audio device yet. The APU
  models what a game can observe without listening: `$4017`'s frame
  sequencer in four- and five-step mode, the frame IRQ, and the four
  length counters (which several timing tests use as a stopwatch).
  The DMC, its DMA and its IRQ are not modelled.
- **Interrupts are sampled at instruction boundaries**, with the
  documented one-instruction delay for `CLI`/`SEI`/`PLP` and the
  NMI-inside-vblank race. An NMI that arrives *inside* the seven cycles
  of BRK or IRQ vectoring, or during sprite DMA, is taken at the next
  boundary instead of interrupting the sequence; `cpu_interrupts_v2`
  tests 2–5 check exactly those cycles and fail. Games almost never
  depend on it; the tests do.
- **The sprite overflow flag has no bug.** The flag is set when a ninth
  sprite is found, as an emulator would; the 2C02's off-by-one and its
  corruption of the sprite scan (which `sprite_overflow_tests` 1–4
  check) are not reproduced. Sprite-0 hit is exact.
- **The MMC3 is the revision B chip**: the counter reloads on zero or
  on a reload flag, and it raises IRQ only when enabled. The earlier
  revision A (`mmc3_test_2`'s `6-MMC3_alt`) behaves differently and
  cannot pass at the same time as `5-MMC3`.
- **A12 filtering is modelled as a low-time threshold**, not as the
  chip's analog filter: an edge counts when A12 has been low for ten
  PPU dots, which rejects the nine-dot gap at a line boundary and
  leaves one clock per line. The phase was measured against the MMC3
  test ROMs, not derived.
- **PAL is not modelled**: the timing is NTSC, and a PAL ROM runs
  slightly fast.
- Cartridges larger than 64 MiB are refused, as are FDS, MMC5, VRC and
  other unimplemented boards. There is no save-state, rewind, cheat
  support or game-genie input.

## The interesting parts

- **One clock per CPU cycle for free.** `bus_read`/`bus_write` call
  `ppu_run(3)` before answering, and `run_frame` ticks whatever cycles
  of the instruction did not touch the bus at its end. The PPU therefore
  sees every access on the right dot, and the CPU stays a plain
  instruction interpreter — the shape `nestest` checks.
- **The frame buffer lives in the PPU.** `Ppu.fb` is the 256×240 words
  the window uploads; the bus, the renderer and the headless PPM writer
  all share it without threading a picture buffer through every call.
- **MMC1's serial port** is five writes of one bit; the fifth write's
  address picks the register, and a write with bit 7 set resets the
  shift register. The checks walk all five registers and both PRG
  windows.
- **MMC3's counter** is clocked by `a12_track`, which watches the
  address the PPU drives each dot: the low/high pattern-byte fetches,
  the sprite slots and the two-tile pre-fetch at the end of a line. A
  rising edge after a long enough low is one scanline.
- **The checks are cartridges, not unit tests.** Each one writes a real
  header, real PRG and real CHR into a `Vec`, parses it through `rom.vl`
  and (where it can) runs it on the machine, so the parser, the mapper
  and the CPU are exercised through the same paths a game takes.
