#!/usr/bin/env bash
# Stock Strata + Qwen3.8-Flash-Next Gyro S on a Valve Steam Machine (SteamOS, 8 GB AMD GPU, 32 GB RAM).
# Run ON the Steam Machine (Desktop Mode terminal, or over SSH). No root needed.
# Measured with this setup: ~235-242 t/s prefill, ~17-19 t/s decode (see STEAM-MACHINE-STRATA-NOTES.md).
#
# MTP stays off: tested with the draft layer really loaded, no decode gain, ~10% lower prefill (see notes).
#
# Verified: install, the first download/launch, the preset and the systemd unit were each run on the
# machine, but not as one single run of this exact file. The preset was originally built by relaunching
# an existing preset with --context 128k --set resident-budget-gib=64 --save-preset.
set -euo pipefail

PRESET=steam-gyro-s-fast
MODELS_DIR="$HOME/strata-models"
PORT=8080

# 1. Install the terminal app (read the installer first)
if [ ! -x "$HOME/.local/bin/strata" ]; then
  curl -fsSL https://github.com/Niko1221/Strata/releases/latest/download/install.sh -o "$HOME/strata-install.sh"
  less "$HOME/strata-install.sh"
  sh "$HOME/strata-install.sh"
fi
export PATH="$HOME/.local/bin:$PATH"
strata --version
mkdir -p "$MODELS_DIR"

# 2. Dry run: shows the engine package and the plan, changes nothing
strata launch --plan --model gyro-s --family gyro --data-dir "$MODELS_DIR" --context 128k --kv q4_0

# 3. Serve. The first run downloads ~55 GiB, then packs the experts (~15 min). Needs ~300 GB free in /home.
#    --set resident-budget-gib=64 is the setting that gave ~+20% decode: the engine keeps experts in its own
#    RAM tier (about 28 GB used of 32 GB), so close Steam and other apps first.
#    --access lan makes it reachable from other machines (API key required, see step 5).
#    systemd-run keeps the server alive after the SSH session ends (nohup/setsid do not on SteamOS).
#    KillMode=process + RemainAfterExit=yes stop systemd killing the engine when the launcher exits.
systemd-run --user --unit=strata-serve --collect \
  --property=KillMode=process --property=RemainAfterExit=yes \
  "$HOME/.local/bin/strata" launch --model gyro-s --family gyro --data-dir "$MODELS_DIR" \
  --context 128k --kv q4_0 --vision off --mtp off --tune skip \
  --set resident-budget-gib=64 \
  --access lan --port "$PORT" --no-tui --yes --restart --save-preset "$PRESET"

# 3b. Model params (sampling defaults, thinking cap). They live in the installed model config, which the
#     launcher copies into every preset at each start, so edit that one, then restart (step 3 again).
#     python3 - <<'EOF'
#     import json, pathlib
#     p = pathlib.Path.home() / ".local/share/strata/install/strata-gyro-gyro-s.json"
#     c = json.loads(p.read_text())
#     c["sampling"] = {"temperature": 1, "top_p": 0.95, "top_k": 20, "min_p": 0}
#     c["reasoning_budget_tokens"] = 8000
#     p.write_text(json.dumps(c, indent=2))
#     EOF

# 4. Follow progress (--no-tui prints no download progress: check the file size instead)
#    journalctl --user -u strata-serve -f
#    du -sh "$MODELS_DIR"
#    ss -ltn | grep ":$PORT "          # listening = ready

# 5. API key and test from another machine (do not paste the key anywhere public)
#    strata launch --show-key --preset "$PRESET"
#    curl http://<steam-machine-ip>:8080/v1/chat/completions -H "Authorization: Bearer $KEY" \
#      -H "Content-Type: application/json" \
#      -d '{"model":"qwen3.8-flash-next-gyro-gyro-s","messages":[{"role":"user","content":"hi"}],"max_tokens":200}'
#    The model emits reasoning_content before content.

# Later, to restart from the saved preset:
#   systemd-run --user --unit=strata-serve2 --collect --property=KillMode=process --property=RemainAfterExit=yes \
#     ~/.local/bin/strata launch --preset steam-gyro-s-fast --access lan --port 8080 --no-tui --yes --restart
# Other commands:
#   strata launch --status | --stop --preset steam-gyro-s-fast | --list-presets
#   strata connect               # Claude Code / OpenCode / Codex CLI setup
#   strata update --check
#
# One-time on a fresh SteamOS: enable SSH and set a password (sshd is off by default)
#   passwd && sudo systemctl enable --now sshd      # then from the Mac: ssh-copy-id deck@<ip>
