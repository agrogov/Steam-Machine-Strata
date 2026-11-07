# Strata on a Valve Steam Machine

Running [Qwen3.8-Flash-Next Gyro S](https://huggingface.co/agentionai/Qwen3.8-Flash-Next-Gyro-GGUF/blob/main/Qwen3.8-Flash-Next-Gyro-S-TQ1_0.gguf) with stock [Strata](https://github.com/Niko1221/Strata) on a Valve Steam Machine (stock SteamOS, 8 GB AMD GPU, 32 GB RAM), served to a Mac over the LAN.

Measured (Strata's own timing line, 128K context): about 235–242 t/s prefill and 17–19 t/s decode. Results vary by run, so read them as ranges. MTP is off on purpose: with the draft layer really loaded it gave no decode gain and about 10% lower prefill (see the notes).

## Quick start

On the Steam Machine (no root, no Ubuntu needed):

```bash
./strata-steam-machine.sh
```

It installs Strata, downloads the model (about 55 GiB, so keep about 300 GB free in `/home`), starts the server as a systemd user unit on `0.0.0.0:8080`, and saves the `steam-gyro-s-fast` preset. The key setting is `--set resident-budget-gib=64`, which gave about +20% decode. It uses about 28 of the 32 GB of RAM, so close Steam and other apps first.

Get the API key and call the server from the Mac:

```bash
strata launch --show-key --preset steam-gyro-s-fast
```

The endpoint is `http://<steam-machine-ip>:8080/v1`, and the model name is `qwen3.8-flash-next-gyro-gyro-s`.

Model params used: temperature 1, top_p 0.95, top_k 20, min_p 0, thinking capped at 8000 tokens (how to set them is in the notes and the script).

## Files

| File | What it is |
|---|---|
| `strata-steam-machine.sh` | Install, serve and save the preset (run on the Steam Machine) |
| `bench.sh` | Benchmark from the Mac: unique ~8K-token prompts, prints prefill and decode speed |
| `bench-long.sh` | Same with ~60K-token prompts |
| `experiment.sh` | Relaunch from a preset with one extra change, to test a setting |
| `STEAM-MACHINE-STRATA-NOTES.md` | Full write-up: setup, SteamOS gotchas, all results, what did and did not help |
| `strata-steam-machine-gyro-s.json` | The [Reddit author](https://www.reddit.com/r/LocalLLaMA/comments/1xft2ae/have_8_gb_of_vram_and_32_gb_of_ram_you_can_run/)'s config adapted as a reference. It is not used for launching |

## Benchmarking

```bash
./bench.sh final 3                       # 3 runs, ~8K tokens
./bench-long.sh long 2                   # 2 runs, ~60K tokens (about 4 minutes each)
HOST=<ip> PRESET=<name> ./bench.sh x 3   # other host or preset
```

The scripts need SSH access to `deck@<host>`. Defaults: host `192.168.1.100`, preset `steam-gyro-s-fast`. The API key is fetched over SSH and never printed.

## SteamOS gotchas

- Anything started from an SSH session dies when it ends. Use `systemd-run --user --property=KillMode=process --property=RemainAfterExit=yes`.
- sshd is off by default. Enable it and set a password with `passwd`.
- `--no-tui` shows no download progress, so check the file size instead.
- Do not `pkill -f "strata launch"` over SSH, because it matches your own SSH command.
- Launching with `--preset NAME` writes the result back to that preset.

## Status

- The install, download, preset, systemd unit and long-context runs (58K and 61K tokens, no out-of-memory kills) were each run on the machine.
- `strata-steam-machine.sh` and the rewritten `bench.sh` have not been run in their final form. Only a syntax check was done on them.
- Not tested: prompts beyond 61K tokens, or a busy desktop session at the same time.

See [STEAM-MACHINE-STRATA-NOTES.md](STEAM-MACHINE-STRATA-NOTES.md) for details.

## License

[MIT](LICENSE)
