# galaga

The neural-galaga "cheats" agent, playing in a window: the game, the
structure-aware observation, and the pretrained actor-critic that
chooses an action every other tick, drawn exactly as the Rust
`infer_cheats` client draws it — the battle starfield behind the game, a
policy panel on the right (one bar per action, the chosen one in orange,
the critic's value below), the upgrade HUD, and the saliency circles
that show which entities moved the decision.

This is a port of `neural-galaga`: the simulation and its rendering, the
815-float observation, the model architecture, the checkpoint loader and
the UI are all reproduced from the Rust sources, and the parts that
produce numbers are checked against them (below).

```sh
target/volec -O2 examples/gpu/galaga/main.vl -o galaga
./galaga                        # the checkpoint in examples/gpu/galaga/checkpoints
./galaga --model /path/to/another.mpk
./galaga --headless             # no display needed: the self-check
./galaga --headless --steps 600 --saliency
```

The window is 368×288 logical pixels of picture (224 of game and 144 of
policy panel), upscaled with nearest-neighbour sampling. The checkpoint
in `checkpoints/best.mpk` is the trained cheats agent; without one the
program stops with the loader's message.

| input | action |
|---|---|
| space | pause / resume |
| `s` | one tick, while paused |
| `v` | saliency circles on / off |
| `1` … `9` | start over at that wave |
| `m` | mute (the sound is not ported; the HUD says MUTE) |
| `q` / Esc | quit |

## The parts

| file | what |
|---|---|
| [assets.vl](assets.vl) | the 392-pixel sprite sheet index and its 38-colour palette, and the 8-pixel bitmap font's glyph rows |
| [draw.vl](draw.vl) | the software frame (a `Vec<u32>` of packed RGBA), alpha-blended rectangles, circle outlines, rotated sprites, the bitmap font |
| [game.vl](game.vl) | the simulation: player, formation, dives, bullets, shotgun, explosions, powerups, shields, the shop, waves, scoring, and its own 224×288 frame |
| [obs.vl](obs.vl) | the 815-float observation — 17 player floats, 36 enemy slots, 8 player and 32 enemy bullet slots, 12 shotgun slots, 4 powerup slots, 14 danger columns — and the two-frame stack |
| [model.vl](model.vl) | the MessagePack checkpoint reader (f16 tensors, shape `[in, out]`), the actor-critic forward pass, `top_k`, and the gradient of the chosen action's log-probability |
| [infer.vl](infer.vl) | the agent's state: the two observations, the top-3 sampling, and the per-entity saliency targets |
| [session.vl](session.vl) | the session: one tick, then the starfield behind the game and the composed 224×288 frame |
| [render.vl](render.vl) | the battle starfield (stars, ten nebulas), the wave-clear and game-over overlays, the HUD, the policy panel, the saliency rings |
| [view.vl](view.vl) | the storage buffer holding the 368×288 frame and the fullscreen nearest-neighbour shader |
| [check.vl](check.vl) | `--headless`: the encoder, the network and its gradients, the frames, the panel and overlays, one GPU readback, then the agent playing |
| [main.vl](main.vl) | the CLI, the window, the phase machine, the keys and the frame loop |

## The numbers it is checked against

`check.vl` recomputes each of these and compares:

| what | expected | where it comes from |
|---|---|---|
| observation, reset / after 450 two-tick steps | `d4fa48b0d8dd7005` / `797598b6182d43f4` | the Rust env's encoder on the same seed and actions (FNV-1a over the float bits) |
| the game's own frame at ticks 1, 2, 300, 600, 900 | five FNV hashes | `neural-galaga-core`'s `fb_ref.rs`, same seed and action cycle |
| the composed session frame at the same ticks | five more FNV hashes | the same reference |
| the policy's value for the reference observation | `40827a80` (the f32 bits) | the checkpoint through Burn's forward pass |
| the saliency gradient's summed magnitude | 129.14 ± 0.15 | the same pass through Burn's autodiff, and a NumPy reference |
| one frame through the real pipeline | every pixel, in BGRA | the framebuffer it was built from |

The frames and the observation match exactly, hash for hash; the
network's sums differ only in the last digits of a dot product, which
is why the gradient is compared with a tolerance. `--steps` then lets
the agent play with no window and prints the final score — another
deterministic number once the sampler is seeded.

## What it shows

- **A software picture on the GPU.** The game, the starfield, the panel,
  the overlays and the text are all drawn into one `u32` per pixel on
  the CPU, then uploaded as a 424 KB storage buffer every frame. The
  shader has no texture or sampler: a fragment's `uv` picks one word and
  unpacks it. On a Retina display the window is exactly five picture
  pixels per screen pixel, so the nearest-neighbour sampler is exact.
- **A checkpoint without a framework.** The Burn `CompactRecorder`
  writes MessagePack: the loader reads a map of little-endian f16
  tensors and widens them to f32, so the network is six `Linear` layers
  and a handful of loops. `top_k` and the sampling are the client's.
- **Gradients by hand.** Saliency is the gradient of the chosen action's
  log-probability with respect to the observation: a one-hot minus the
  softmax at the logits, then each layer's transpose and ReLU mask back
  to the input. The per-slot sums show which enemy, bullet or powerup
  the decision leaned on, and the overlay rings them.
- **The client's cadence.** The agent looks at the world every second
  tick (`FRAME_SKIP`), with the observation from the tick before, and
  the saliency is recomputed on the same cadence — not every frame.

The sound is the one part not ported: the client starts muted, the HUD
says MUTE, and `m` toggles the label.

New to vole? `volec guide gpu` and `volec guide window` cover the APIs
this example uses.
