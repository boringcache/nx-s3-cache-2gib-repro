#!/usr/bin/env bash
# Reproduces nrwl/nx#36943: @nx/s3-cache cannot store a task output that holds a
# single file larger than 2 GiB, and the task still reports success.
#
# Usage:   pnpm repro          (with `pnpm s3rver` running in another terminal)
# Needs:   an Nx key (NX_KEY=... or `pnpm exec nx register <key>`), see README.md
set -u
cd "$(dirname "$0")" || exit 1

# s3rver accepts any well-formed credentials.
export AWS_ACCESS_KEY_ID=S3RVER
export AWS_SECRET_ACCESS_KEY=S3RVER
# One process per step, no daemon and no plugin workers: keeps the verbose output readable.
export NX_DAEMON=false
export NX_ISOLATE_PLUGINS=false

NX="pnpm exec nx"

step() {
  printf '\n\n################################################################\n# %s\n################################################################\n' "$1"
}

if ! curl -s -o /dev/null http://127.0.0.1:4568/; then
  echo "s3rver is not reachable on http://127.0.0.1:4568 - run 'pnpm s3rver' in another terminal first." >&2
  exit 1
fi

step "0. Clear the local Nx cache"
$NX reset

step "1. build-under (1900 MiB file) with NX_VERBOSE_LOGGING=true - expected: task runs, upload succeeds silently"
NX_VERBOSE_LOGGING=true $NX run big:build-under
echo "exit code: $?"

step "2. build-over (2200 MiB file) with NX_VERBOSE_LOGGING=true - expected: 'Failed to upload to the S3 Bucket' + ERR_FS_FILE_TOO_LARGE, exit code still 0"
NX_VERBOSE_LOGGING=true $NX run big:build-over
echo "exit code: $?"

step "3. build-over again WITHOUT NX_VERBOSE_LOGGING - expected: nothing indicates that the upload failed"
$NX reset
$NX run big:build-over
echo "exit code: $?"

step "4. Objects in the bucket - expected: one object (build-under's hash), nothing for build-over"
find .s3rver/nx-cache -type f | sort

step "5. Clear the local cache and rerun both - expected: build-under is restored '[remote cache]', build-over reruns its command"
$NX reset
rm -rf big/dist
$NX run big:build-under
echo "exit code: $?"
$NX run big:build-over
echo "exit code: $?"

step "6. Disk usage (the .bin files are sparse; a remote-cache restore writes real bytes)"
du -sh big/dist .nx/cache .s3rver 2>/dev/null
