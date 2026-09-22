# Nx large-output validation

This fork evaluates BoringCache against
[Nx #36943](https://github.com/nrwl/nx/issues/36943), which reported that
`@nx/s3-cache` could not upload a single output larger than 2 GiB. It is not a
validation of the commercially shortlisted operator in
[Nx #37052](https://github.com/nrwl/nx/issues/37052). That issue concerns a
failed remote write turning an otherwise successful run into a failure.

Nx #36943 closed on 20 September 2026. The reporter's reproducer remains useful
as a large-file correctness check, but it should no longer be treated as an
open prospect pain signal.

## Integration

The current workflow pins BoringCache One v1.31.0 at
`9ca311f9b247835b3cc87639321c79bac8018145`. GitHub OIDC supplies the cache
capability. The workflow uses Nx's native HTTP remote-cache protocol on clean
Ubuntu 24.04 x86-64 and macOS 15 ARM64 runners.

The fixture runs two cacheable tasks whose declared outputs are sparse,
zero-filled files of 1,900 MiB and 2,200 MiB. A fresh tag isolates every run.
The cold jobs publish; the warm jobs restore only. Warm jobs compare both file
sizes and SHA-256 hashes with their cold producer.

The upstream reproducer contains only one source commit, so there is no honest
rolling-source comparison for this fork.

## BoringCache v1.31 result

All four jobs passed in
[run 35701458488](https://github.com/boringcache/nx-s3-cache-2gib-repro/actions/runs/35701458488).
Both warm jobs reported two remote-cache hits, and all restored sizes and hashes
matched their producer.

| Runner | Cold whole job | Cold harness | Warm whole job | Warm harness | Warm task hits |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ubuntu 24.04 x86-64 | 1m07s | 49s | 1m18s | 42s | 2/2 |
| macOS 15 ARM64 | 1m06s | 35s | 59s | 27s | 2/2 |

The harness time includes both Nx invocations and reading 4.00 GiB of restored
output to calculate SHA-256 hashes. This is a correctness workload, not a useful
build-speed benchmark. In particular, the Ubuntu warm job spent longer in setup
than its cold job, so whole-job time cannot be used as a release comparison.

## Storage result

BoringCache's retained run summary recorded:

- four cold task misses and four warm task hits;
- zero cache read or write errors;
- 8,352,748 bytes written across the two cold platforms; and
- 8,352,748 bytes read across the two warm platforms.

Each platform therefore stored and restored about 3.98 MiB for 4,299,161,600
logical output bytes. That compression ratio comes from sparse, zero-filled
fixtures. It proves that the native cache round-trips files on both sides of the
2 GiB boundary; it does not estimate storage or transfer for a real C++ archive.

The warm local Nx cache occupied about 4,198,400 KiB on each runner after
materialization. BoringCache reduced network bytes for this fixture, but Nx
still materialized the full local outputs before the harness hashed them.

## Commercial qualification

This fork does not validate the shortlisted #37052 operator:

- #36943 was filed by a different user and is now closed.
- #37052 concerns failure semantics, not large-file handling or speed.
- PR [#37054](https://github.com/nrwl/nx/pull/37054) is open and may remove the
  immediate failure mode in Nx itself.
- BoringCache has not yet run a controlled remote-write outage against the
  #37052 scenario.

The next valid step for #37052 is a small reproduction that completes a task,
cuts the remote cache connection during the write, and records the process exit
status with Nx 23.0.2, the proposed upstream fix, and BoringCache's Nx adapter.
Company identity and willingness to evaluate another cache service still need
qualification before commercial outreach.
