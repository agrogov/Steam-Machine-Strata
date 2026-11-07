#!/usr/bin/env bash
# Run on the Mac. Relaunch the Steam Machine server from a preset with extra launch args, wait until it
# serves, then print the applied settings. Used for every experiment in the notes.
# Usage: experiment.sh UNIT_NAME [strata launch args...]
#   experiment.sh exp3 --set resident-budget-gib=64
#   experiment.sh exp5 --context 32k --set resident-budget-gib=64
#   experiment.sh exp6 --context 128k --set resident-budget-gib=64 --save-preset steam-gyro-s-fast
# Then: ./bench.sh LABEL 3     (PRESET=... if the engine log is under another preset name)
# Note: launching with --preset NAME writes the result back to that preset (the 32K test overwrote
# steam-gyro-s that way), so base experiments on a throwaway preset or save the one you want to keep.
set -euo pipefail
HOST=${HOST:-192.168.1.100}
BASE=${BASE:-steam-gyro-s}
U=$1; shift
ssh deck@$HOST "systemd-run --user --unit=$U --collect --property=KillMode=process --property=RemainAfterExit=yes /home/deck/.local/bin/strata launch --preset $BASE $* --access lan --port 8080 --no-tui --yes --restart >/dev/null 2>&1
for i in \$(seq 1 60); do sleep 10; journalctl --user -u $U --no-pager | grep -q 'Strata is serving' && break; done
journalctl --user -u $U --no-pager | grep -i -E 'unknown|warn|\[!\]|serving|error' | cut -c1-200 | tail -5
# values wrap onto the next line in the generated JSON, so strip newlines before grepping
tr -d '\n ' < ~/.local/state/strata/launch/$BASE.json | grep -o -E '\"--(kv-resident|kv-grow|vram-reserve-mib|pcie-frac|max-context)\",\"?[^\",]*'
free -m | head -2"
