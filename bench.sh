#!/usr/bin/env bash
# Run on the Mac (needs ssh access to deck@HOST).
# Usage: [HOST=ip] [PRESET=steam-gyro-s-fast] [LINES=190] bench.sh LABEL [RUNS]
#   LINES=190  -> ~8K-token prompts, LINES=1400 -> ~60K tokens (prefill takes ~4 min each)
# Sends unique prompts (no cache reuse) and prints Strata's own timing line from the engine log.
# The API key is fetched over SSH and never printed.
set -euo pipefail
HOST=${HOST:-192.168.1.100}
PRESET=${PRESET:-steam-gyro-s-fast}
LINES=${LINES:-190}
LABEL=${1:-run}; RUNS=${2:-3}
LOG=/home/deck/.local/state/strata/launch/$PRESET.engine.log
KEY=$(ssh deck@$HOST "~/.local/bin/strata launch --show-key --preset $PRESET 2>&1" | grep -oE 'sk-strata-[A-Za-z0-9_-]+' | head -1)
for i in $(seq 1 "$RUNS"); do
  PROMPT=$(python3 - "$LINES" <<'EOF'
import random, sys
n = random.randint(0, 10**9)
lines = [f"def func_{n}_{j}(x): return (x * {random.randint(2,99)} + {random.randint(1,999)}) % {random.randint(7,97)}  # helper {j}" for j in range(int(sys.argv[1]))]
print(f"[{n}] Here is some code:\n" + "\n".join(lines) + "\n\nIn one sentence, what does this file do? Answer briefly.")
EOF
)
  BEFORE=$(ssh deck@$HOST "wc -l < $LOG")
  curl -s -m 1200 http://$HOST:8080/v1/chat/completions -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"model":"qwen3.8-flash-next-gyro-gyro-s","messages":[{"role":"user","content":sys.argv[1]}],"max_tokens":300}))' "$PROMPT")" > /dev/null
  ssh deck@$HOST "tail -n +$((BEFORE+1)) $LOG | grep -E 'strata serve: prompt [0-9]+ tokens' | tail -1" | sed "s/^/[$LABEL #$i] /" | cut -c1-230
done
