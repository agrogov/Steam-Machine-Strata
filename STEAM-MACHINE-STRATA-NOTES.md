# Strata + Qwen3.8-Flash-Next Gyro S on a Valve Steam Machine

Everything done and measured in this session (2026-11-01). All numbers come from Strata's own per-request timing line in the engine log, not from the client side.

## Hardware and software

| | |
|---|---|
| Machine | Valve Steam Machine, SteamOS 3.9.5 (stock, no Ubuntu needed), kernel 7.2.7-valve2 |
| GPU | AMD Navi 33, 8 GB GDDR6 |
| CPU | custom AMD, 6 cores / 12 threads |
| RAM | 32 GB (31.2 GiB usable), swap 17 GB |
| Storage | NVMe, about 2.5 GB/s |
| Strata | terminal 0.2.9, engine 0.1.55, package `linux-x86_64-hip-rx7900` |
| Model | Qwen3.8-Flash-Next Gyro S, TQ1_0 GGUF, 58.5 GB total, served as `qwen3.8-flash-next-gyro-gyro-s` |

Strata installs under `~/.local/share/strata` and `~/.local/bin/strata` with no root. Models are in `~/strata-models`.

## Decisions

- Stock Strata, not PR #3267 (LoRA support), because that PR is CUDA-only and the GPU is AMD.
- Server on `0.0.0.0:8080` (`--access lan`) with an API key, so it is reachable from a Mac. Without a key it returns 401. `strata launch --show-key` prints the key.

## Install

```bash
curl -fsSL https://github.com/Niko1221/Strata/releases/latest/download/install.sh -o ~/strata-install.sh
less ~/strata-install.sh      # read it first
sh ~/strata-install.sh
export PATH="$HOME/.local/bin:$PATH"
strata launch --plan --data-dir ~/strata-models
```

The first launch downloads about 55 GiB and then packs the experts (about 15 minutes after the download).

## SteamOS gotchas

- Processes started from an SSH session die when it ends (nohup and setsid did not help). Use a user systemd unit with `KillMode=process`, otherwise the unit is killed when the launcher exits after loading the model:

  ```bash
  systemd-run --user --unit=strata-serve --collect \
    --property=KillMode=process --property=RemainAfterExit=yes \
    ~/.local/bin/strata launch --preset steam-gyro-s-fast \
    --access lan --port 8080 --no-tui --yes --restart
  ```

- `--no-tui` prints no download progress. Measure progress by file size growth.
- `watch` over SSH needs `ssh -t`.
- Do not `pkill -f "strata launch"` over SSH: the pattern matches the SSH command itself.
- sshd is off by default: enable it and set a password with `passwd` first.

## Benchmark method

`bench.sh LABEL [RUNS]` sends unique prompts of about 8K tokens (no cache reuse), max_tokens 300, then reads the `strata serve: prompt N tokens ...` line from the engine log for prefill and decode speed. `bench-long.sh` is the same with about 60K tokens (1400 lines). Note: `bench-long.sh` still points at the old log path (`steam-gyro-s.engine.log`), so read the preset's own engine log for its timings.

Decode speed varies run to run with how many speculative drafts are accepted (for example 0 of 3 up to 26 of 47), so each row is a range over 3 runs.

## Results (about 8K-token prompts)

| Config | Prefill (tok/s) | Decode (tok/s) | Notes |
|---|---|---|---|
| Baseline (`--tune skip`, 128K, q4_0) | 219–240 | 15.1–15.9 | page cache holds the experts, "used" RAM about 5 GB |
| After `--tune quick --retune` | 237–239 | 14.5–17.2 | tuner result: "already fastest", nothing changed |
| `kv-resident=20480`, `vram-reserve-mib=900`, `STRATA_RESIDENT_HEADROOM_GIB=4` | 227–229 | 14.8–15.5 | no gain, prefill about 4% lower |
| `pcie-frac=0.35` alone | 239 | 14.8–16.0 | no change |
| `resident-budget-gib=64` | 232–233 | 17.3–19.2 | experts move into the engine's own RAM tier, about 28 GB used |
| budget64 + `kv-grow=1` | 241 | 17.9–18.6 | `kv-grow` may not have applied (config still showed `kv-resident` 32768) |
| budget64 + 32K context | 242 | 18.6–19.8 | small extra decode gain, but loses long context |
| **budget64 + 128K context (saved preset)** | about 234–242 | about 17.5–18.5 | `steam-gyro-s-fast` |

Long context with the saved preset:

| Prompt | Prefill (tok/s) | Decode (tok/s) |
|---|---|---|
| 57,727 tokens | 234.5 | 17.6 |
| 60,546 tokens | 236.4 | 17.9 |

Each took about 4 minutes to prefill. Memory during the test: available RAM bottomed out at about 3.4 GB, swap went from 173 MB to 339 MB, no OOM kill, service stayed active. Not tested: beyond 61K tokens, or with Steam or a desktop session running.

## MTP

### The launcher never loaded it
The OP and several commenters run with `--mtp off` because on NVIDIA the draft head costs VRAM and prefill speed. My first launch copied that. Later I tried `--mtp on`, but it changed nothing:
- The saved config said `"mtp": true`, but the engine args had no `--mtp <path>`, `~/strata-models/mtp` did not exist, and the log said "+0 MiB for the draft head". The launcher treated the model as already installed and never fetched the draft layer.
- So my earlier `--mtp off` vs `--mtp on` comparison (decode 17.2-17.3 vs 18.2-18.4) compared two runs without MTP. It was noise.
- The "drafts accepted" figures in those runs came from Strata's other drafting (`--spec 4`, suffix drafts), not MTP.

### Real MTP (draft layer actually loaded)
I built the draft layer by hand with Strata's tools (`mtp_fetch.py`, `mtp_pack.py`, `mtp_rt.py`, plus `draft_vocab.bin`; steps in docs/GYRO.md of the Strata source) into `~/strata-models/mtp/rt`, and passed it with `--set mtp=/home/deck/strata-models/mtp/rt --mtp on --drafting mtp --set spec-min-p=0.5`. Same 128K, q4_0, `resident-budget-gib=64`. The engine log confirmed `strata mtp: draft layer loaded, 820 MiB of VRAM` and `draft head over 106299 tokens (212.9 MiB)`. The expert cache shrank from 2225 to 1179 slots.

| Run (about 8K tokens) | Prefill (tok/s) | Decode (tok/s) | Drafts accepted |
|---|---|---|---|
| 1 | 210.9 | 15.6 | 86 of 190 |
| 2 | 210.3 | 18.4 | 95 of 142 |
| 3 | 210.3 | 16.9 | 123 of 223 |
| Control, MTP off | 229-234 | 17.2-17.3 | n/a |

Result on this machine: no decode gain (mean about 17.0 vs about 17.2, inside run-to-run noise) and prefill about 10% lower (210 vs 232). The draft layer takes about 1 GB of the 8 GB VRAM, which halves the expert cache, and that cancels what the accepted drafts gain. Acceptance was 45-67%. The "drafts accepted" count in the timing line may include suffix drafts as well as MTP, so I cannot give an MTP-only acceptance rate. Only 3 runs, one prompt type, 8K context; I did not run MTP at long context. Conclusion: `--mtp off` is the right choice for 8 GB VRAM, for a measured reason this time.

## Model params (sampling and thinking cap)

Set on the machine: temperature 1, top_p 0.95, top_k 20, min_p 0, and `reasoning_budget_tokens` 8000. They are top-level keys of the model's run config, not engine args, so `--set` does not take them.

- The launcher builds every preset's config (`~/.local/state/strata/launch/<preset>.json`) from the model's installed config, `~/.local/share/strata/install/strata-gyro-gyro-s.json`, and rewrites it at each start. Edit only the installed one: an edit to the preset file is lost on the next launch (I lost one that way).
- Keys added: `"sampling": {"temperature": 1, "top_p": 0.95, "top_k": 20, "min_p": 0}` and `"reasoning_budget_tokens": 8000`. A backup was saved as `strata-gyro-gyro-s.json.bak`.
- Checked after restarting: both the installed config and the generated `steam-gyro-s-fast.json` hold the values, and the engine has no `--mtp` path. I did not send a request to confirm the sampling defaults take effect.

## Stability warning

During the MTP test the Steam Machine rebooted (uptime 0 minutes afterwards). The runs just before it were slow (prefill 84 and 37 t/s, decode 4.2 t/s) and the engine log showed 176,994 major page faults, which looks like memory thrashing. The cause was not confirmed. A desktop session was logged in, and `resident-budget-gib=64` leaves only about 3.5–4 GB available out of 32 GB. After the reboot, a clean restart of the same preset gave normal numbers again. The earlier "no OOM" result applies only to the long-context test with no other load.

## What I learned

- **`resident-budget-gib=64` was the only setting that mattered** (about +20% decode). With it the engine log shows hundreds of thousands of experts in its RAM tier ("RAM 276585 blobs", up from 0).
- **RAM was never idle.** Without that setting, the experts sat in the OS page cache (about 28 GB "buff/cache", process RSS 28 GB, file-backed). A monitor that shows only "used" memory hides this.
- During decode the OS read about 11 MB per request from the SSD, so storage is not the decode bottleneck. The limit is moving missed experts from RAM to an 8 GB GPU.
- **Prefill stays at about 235–242 tok/s in every config.** Nothing I tried changed it.
- Not helpful here: `pcie-frac 0.35`, `kv-resident 20480`, a larger VRAM reserve, and the quick tuner.
- Not tried: `--adapt-*`, `--spec-min-p 0.70`, `STRATA_PREFILL_CPU_SHARE=0`, `--thorough` tune, `--pool-cores`.
- `--set KEY=VALUE` only warns on unknown names. Check the generated config (`~/.local/state/strata/launch/<preset>.json`) to see what was applied. Flags with values wrap onto the next line in that JSON, so strip newlines before grepping.
- The Strata 0.1.55 issue [#4822](https://github.com/Niko1221/Strata/issues/4822) (prefill 40–60% slower at first, recovering after 30–45 minutes) was reported on an RX 9070 XT. I did not see a warm-up curve here.

## Web search

No ready-made Strata config for 8 GB VRAM with 16–32 GB RAM exists that I could find. Official guidance (vramcalculator, the XeStrata README) is 12 GB or more of VRAM. XeStrata is a separate project and needs rocBLAS support (Navi 33 / gfx1102 needs Fedora 44). The Reddit post remains the only 8 GB data point.

## Presets on the machine

- `steam-gyro-s-fast`: 128K context, q4_0 KV, `resident-budget-gib=64`, MTP off, the model params above. Use this one. The server is running it.
- `steam-gyro-s`: overwritten by the 32K test, so it is now 32K context.
- `steam-gyro-s-mtp`: deleted (it was the real-MTP test config, and its draft layer is deleted too).

The engine config and log for a preset are at `~/.local/state/strata/launch/<preset>.json` and `<preset>.engine.log`.

## Files in this folder

- `strata-steam-machine.sh`: install script (draft, not updated with the results above)
- `strata-steam-machine-gyro-s.json`: the Reddit author's config adapted as a reference (not used for launching)
- `bench.sh`, `bench-long.sh`: benchmark scripts

## Replicate

On the Steam Machine: `./strata-steam-machine.sh` (install, download, serve as a systemd user unit, save the `steam-gyro-s-fast` preset).
On the Mac:

```bash
./bench.sh final 3                 # ~8K-token prompts, Strata's own prefill/decode timing
./bench-long.sh long 2             # ~60K-token prompts
./experiment.sh exp7 --set resident-budget-gib=64 --set <other>=<value>   # relaunch with one change, then bench.sh
HOST=<ip> PRESET=<name> ./bench.sh ...   # other host or preset
```

Syntax of all four scripts was checked. `bench.sh` was rewritten after the last benchmark run (preset and prompt size are now parameters), so it has not been re-run in its final form.
