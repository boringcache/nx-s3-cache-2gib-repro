# nrwl/nx#36943 — `@nx/s3-cache` cannot store a task output that contains a single file larger than 2 GiB

`@nx/s3-cache` packs a task's outputs by reading every file into memory with
`fs.promises.readFile`. Node.js refuses to read a file larger than 2 GiB
(`RangeError [ERR_FS_FILE_TOO_LARGE]`), so the tarball is never built and the
upload never happens. The plugin catches the error, prints it only when
`NX_VERBOSE_LOGGING=true` is set, and returns `false`; Nx discards that return
value, so the task is reported as successful with exit code 0. The entry never
reaches the bucket, and every later run with a cleared local cache is a remote
miss for that hash. A 1900 MiB output uploads fine; a 2200 MiB output does not.
Reproduced on macOS with Node v22.20.0, `nx@22.6.3`, `@nx/s3-cache@5.0.2`.

## Prerequisites

- Node.js 22 (tested with v22.20.0) and pnpm 10 (tested with 10.33.2)
- `bash`, `curl`, `truncate` (present on macOS and Linux)
- **An Nx key.** `@nx/s3-cache` refuses to activate without one and prints:

  ```
   NX   No self-hosted cache key found. S3 cache will not be used.

  You can register a key for free by using `nx register`.
  ```

  Provide it as the `NX_KEY` environment variable (a bogus value changes the
  message to `Failed to decode the Nx key. Please double-check the key
  provided. (0)`, so the variable is read) or run
  `pnpm exec nx register <key>`, which writes `.nx/key/key.ini`. That file is
  gitignored here and survives the `nx reset` calls in `repro.sh`. The
  `@nx/key` package is obfuscated, so this was established by running it, not
  by reading it.
- Disk: the two output files have an apparent size of 4.1 GiB, but
  `truncate` creates sparse files, so they cost nothing on disk, and Nx's
  local cache copy of a freshly built output stays sparse. A remote cache
  restore writes real bytes: after step 5, `.nx/cache` holds 1.9 GiB of real
  zeros for the restored `under.bin` (`big/dist` stays at 0 B because Nx
  clones the restored files on APFS). The gzipped entry in the bucket is
  1.9 MiB. The pack step also holds the whole 1900 MiB file in memory.
- No AWS account: `s3rver` (an in-process S3 stand-in) serves the bucket on
  `http://localhost:4568`. It accepted the AWS SDK 3.1000 request checksums as
  is; no `AWS_REQUEST_CHECKSUM_CALCULATION` override was needed.

npm marks `@nx/s3-cache@5.0.2` as deprecated
(`https://nx.dev/docs/reference/deprecated/self-hosted-cache-packages`).
The latest 5.0.7 has the identical `readFile` call at the same line, so the
version pin is not what makes this reproduce.

## Steps

```sh
pnpm install

# terminal 1 — local S3 on 127.0.0.1:4568 with a bucket named nx-cache
pnpm s3rver

# terminal 2 (or `pnpm exec nx register <key>` once, then plain `pnpm repro`)
NX_KEY=<your key> pnpm repro
```

`repro.sh` sets dummy `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (s3rver
accepts anything well-formed), `NX_DAEMON=false` and
`NX_ISOLATE_PLUGINS=false` (readable verbose output), then:

0. `nx reset` — clears the local cache so every task really runs.
1. `NX_VERBOSE_LOGGING=true nx run big:build-under` — 1900 MiB output.
2. `NX_VERBOSE_LOGGING=true nx run big:build-over` — 2200 MiB output.
3. `nx reset`, then `nx run big:build-over` **without** `NX_VERBOSE_LOGGING`.
4. Lists the objects s3rver holds in `.s3rver/nx-cache/`.
5. `nx reset`, `rm -rf big/dist`, then runs both targets again.
6. `du -sh big/dist .nx/cache .s3rver`.

The whole script takes well under a minute.

## Layout

- `nx.json` — the `s3` block: `endpoint: http://localhost:4568`,
  `forcePathStyle: true`, `region: us-east-1`, `bucket: nx-cache`,
  `cacheKeyPrefix: nx-cache`, `localMode: read-write`, `ciMode: read-write`,
  `disableChecksum: true`. Nx picks the plugin up automatically because the
  package is installed (`nx/src/tasks-runner/cache.js` resolves
  `@nx/s3-cache` and calls its `getRemoteCache()`).
- `big/project.json` — one project with two cacheable `nx:run-commands`
  targets, both with `outputs: ["{projectRoot}/dist"]`:
  - `build-under`: `rm -rf dist && mkdir dist && truncate -s 1900M dist/under.bin`
  - `build-over`: `rm -rf dist && mkdir dist && truncate -s 2200M dist/over.bin`
- `repro.sh` — the sequence above. `pnpm repro` runs it.

## Expected vs observed

| Step | Expected | Observed |
| --- | --- | --- |
| 1 `build-under` (1900 MiB), verbose | task runs, entry is uploaded, exit 0 | as expected: no error, exit 0, one object appears in the bucket |
| 2 `build-over` (2200 MiB), verbose | task runs, entry is uploaded, exit 0 | `NX Failed to upload to the S3 Bucket` + `{ "code": "ERR_FS_FILE_TOO_LARGE" }`, then `Successfully ran target build-over`, exit 0 |
| 3 `build-over`, not verbose | same as 2 | identical to a healthy run: not one line mentions the failed upload, exit 0 |
| 4 bucket contents | two objects | one object, `build-under`'s hash `8701016355051054136`; nothing for `build-over` |
| 5 rerun with empty local cache | both `[remote cache]` | `build-under` is `[remote cache]`; `build-over` re-executes its command |

## Observed output

Captured from `pnpm repro 2>&1 | tee repro.log` on macOS, Node v22.20.0,
`nx@22.6.3`, `@nx/s3-cache@5.0.2`, `s3rver@3.7.1`. Trimmed to the decisive
lines; blank lines and the key check's `Licensed to <licensee>.` line are
removed.

Step 1, `NX_VERBOSE_LOGGING=true nx run big:build-under` — clean:

```
> nx run big:build-under
> rm -rf dist && mkdir dist && truncate -s 1900M dist/under.bin && ls -l dist
-rw-r--r--  1 user  staff  1992294400 Sep  8 10:45 under.bin
 NX   Successfully ran target build-under for project big
exit code: 0
```

Step 2, `NX_VERBOSE_LOGGING=true nx run big:build-over` — the upload fails,
the task still succeeds:

```
> nx run big:build-over
> rm -rf dist && mkdir dist && truncate -s 2200M dist/over.bin && ls -l dist
-rw-r--r--  1 user  staff  2306867200 Sep  8 10:45 over.bin
 NX   Failed to upload to the S3 Bucket
{
  "code": "ERR_FS_FILE_TOO_LARGE"
}
 NX   Successfully ran target build-over for project big
exit code: 0
```

Step 3, `nx run big:build-over` without `NX_VERBOSE_LOGGING` (local cache
cleared first) — nothing hints at the failure:

```
> nx run big:build-over
> rm -rf dist && mkdir dist && truncate -s 2200M dist/over.bin && ls -l dist
-rw-r--r--  1 user  staff  2306867200 Sep  8 10:45 over.bin
 NX   Successfully ran target build-over for project big
exit code: 0
```

Step 4, objects in the bucket — only `build-under`'s entry exists:

```
.s3rver/nx-cache/nx-cache/8701016355051054136._S3rver_metadata.json
.s3rver/nx-cache/nx-cache/8701016355051054136._S3rver_object
.s3rver/nx-cache/nx-cache/8701016355051054136._S3rver_object.md5
```

Step 5, local cache cleared, both targets again — `build-under` is a remote
hit, `build-over` is a remote miss and runs its command a third time:

```
> nx run big:build-under  [remote cache]
> rm -rf dist && mkdir dist && truncate -s 1900M dist/under.bin && ls -l dist
-rw-r--r--  1 user  staff  1992294400 Sep  8 10:45 under.bin
 NX   Successfully ran target build-under for project big
Nx read the output from the cache instead of running the command for 1 out of 1 tasks.
exit code: 0
> nx run big:build-over
> rm -rf dist && mkdir dist && truncate -s 2200M dist/over.bin && ls -l dist
-rw-r--r--  1 user  staff  2306867200 Sep  8 10:45 over.bin
 NX   Successfully ran target build-over for project big
exit code: 0
```

Step 6, disk usage after the remote restore:

```
  0B	big/dist
1.9G	.nx/cache
1.9M	.s3rver
```

What the plugin's `readFile` call receives for the 2200 MiB file, measured
directly with Node v22.20.0 (`String(e)` and the `JSON.stringify(e, null, 2)`
the plugin prints):

```
RangeError [ERR_FS_FILE_TOO_LARGE]: File size (2306867200) is greater than 2 GiB
{
  "code": "ERR_FS_FILE_TOO_LARGE"
}
```

The 1900 MiB file reads without error (1992294400 bytes < 2^31 - 1).

## Where it happens

All paths are inside `node_modules/@nx/s3-cache/` (version 5.0.2; the bundle
keeps the original source paths as comments).

- **The read:** `index.js:194`, in `createPack()` (bundled from
  `libs/nx-packages/powerpack-utils/src/lib/tar.ts`, function starts at line
  170):

  ```js
  const fileContents = await (0, import_promises.readFile)(filePath);
  ```

  Every output file is read fully into memory and handed to `tar-stream`'s
  `pack.entry(header, buffer)`; there is no streaming path. Node's
  `fs.promises.readFile` rejects any file larger than 2 GiB with
  `ERR_FS_FILE_TOO_LARGE`. Same line in `@nx/s3-cache@5.0.7`.
- **The swallow:** `index.js:492-535`, `S3Storage.put()` (bundled from
  `libs/nx-packages/s3-cache/src/s3-storage.ts`). The `catch` prints
  `Failed to upload to the S3 Bucket` with `JSON.stringify(e, null, 2)` only
  when `VERBOSE_LOGGING` is true (`index.js:388`:
  `process.env.NX_VERBOSE_LOGGING === "true"`), then `return false` at
  line 534.
- **The discard:** `node_modules/nx/src/tasks-runner/cache.js:111`
  (`nx@22.6.3`): `await this.remoteCache.store(...)` — the boolean is never
  read, so the task result is unaffected.

## Real S3 / Cloudflare R2

The same happens against a real bucket: the failure is in the local
`readFile`, before any request is made. Swap `endpoint`, `region`, `bucket`
in `nx.json` and use real `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (or
`accessKeyId`/`secretAccessKey` in the `s3` block); `forcePathStyle: true` and
`disableChecksum: true` are what R2 needs as well.

## Versions

- `nx` 22.6.3
- `@nx/s3-cache` 5.0.2 (depends on `@nx/key` 5.0.2, `@aws-sdk/lib-storage` 3.1000.0, `tar-stream` ^3.1.7)
- `s3rver` 3.7.1
- Node.js v22.20.0, pnpm 10.33.2, macOS
