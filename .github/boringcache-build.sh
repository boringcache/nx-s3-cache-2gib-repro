#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$RUNNER_TEMP/validation"
for size in under over; do
  pnpm exec nx run "big:build-$size" --output-style=static 2>&1 | tee "$RUNNER_TEMP/validation/$size.log"
  if [[ "${VALIDATION_PHASE:-cold}" == warm ]]; then
    grep -q '\[remote cache\]' "$RUNNER_TEMP/validation/$size.log"
  fi
  shasum -a 256 "big/dist/$size.bin" >> "$RUNNER_TEMP/validation/sha256.txt"
  wc -c < "big/dist/$size.bin" >> "$RUNNER_TEMP/validation/sizes.txt"
done
git rev-parse HEAD > "$RUNNER_TEMP/validation/source.txt"
