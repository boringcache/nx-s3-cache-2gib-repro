# Nx validation

Both 1,900 MiB and 2,200 MiB outputs were restored from BoringCache on fresh Linux and macOS runners, with matching SHA-256 hashes and sizes. All four jobs passed in [run 34319793797](https://github.com/boringcache/nx-s3-cache-2gib-repro/actions/runs/34319793797).

| Runner | Cold job | Warm job | Warm task hits |
|---|---:|---:|---:|
| Ubuntu 24.04 | 57 s | 53 s | 2/2 |
| macOS 15 | 60 s | 49 s | 2/2 |

BoringCache recorded four cold misses, four warm hits, and zero cache errors. These are single samples, including setup and file verification. The sparse zero-filled fixture establishes large-file correctness; its approximately 4.18 MB of cache traffic per platform is not evidence of realistic deduplication or build speed. The original S3 comparison requires the reporter's Nx license key and was not rerun.

Integration uses One v1.21.0, pinned to `90111526eb218a7f1e119ac2b29f765bd4d82734`, with GitHub OIDC. The S3 plugin was removed so Nx selects the native HTTP cache. Upstream source: `5f3c091f4787bd94c64e471d2182930b1b88d0d8`; validation source: `53fbe015b0d1c05d19e471d86bc8a747a12f2760`. The upstream reproducer has no earlier commit sequence for a rolling comparison.
