#!/usr/bin/env bash
# ~60K-token prompts. Usage: bench-long.sh LABEL [RUNS]
LINES=1400 exec "$(dirname "$0")/bench.sh" "${1:-long}" "${2:-2}"
