# setup-mago

Installs the [mago](https://github.com/carthage-software/mago) PHP toolchain in GitHub Actions.

```yaml
- uses: chaotic-ground/setup-mago@d79272ad1380980e87ff0c7da01b7131ccb0083b  # v1.1.0
  with:
    version: "1.29.0"
- run: mago format --check
- run: mago lint
```

Pin by commit SHA, which is what GitHub recommends for third-party actions. A tag is a ref this
repository can repoint at any commit, so anyone who takes over the repository reaches every
workflow that follows one; a SHA names the code you reviewed. No moving major tag is published
here, for that reason.

## Inputs

| Input | Default | Description |
|---|---|---|
| `version` | detected | Version to install, without a leading `v` (e.g. `1.29.0`), or `latest`. Unset means: read the project's composer files. |
| `working-directory` | workspace | Where the composer files are read from when `version` is unset. |
| `sha256` | — | Expected sha256 of the release archive. Verified before install when set, and can be stated in `composer.json` instead. |
| `token` | — | Authenticates the git request that lists tags, and nothing else. |

| Output | Description |
|---|---|
| `version` | The version installed, with `latest` and any range resolved. |
| `sha256` | The checksum the archive was verified against, empty when none was stated. |

With no `version`, the version comes from the project itself, in this order: `extra.mago-version`
in `composer.json`, then the `carthage-software/mago` entry in `composer.lock`, then the one in
`composer.json`, and the latest release if the project states none. A requirement may be a range
(`^1.29`, `~1.29.0`, `>=1.0 <2.0`, `1.29.*`, `a || b`), and then the newest release inside it is
installed.

`extra` comes first because a project that installs mago from its release archive rather than
through composer has nowhere else to put the version — and it can put the checksum beside it:

```json
{
    "extra": {
        "mago-version": "1.29.0",
        "mago-sha256": "5e99d1232fa93e6adc6feaaddaf2b46c148b2990173cdcf18400b474646bf046"
    }
}
```

Then no workflow repeats either value. The checksum differs per platform, so a project that
installs on more than one states it per target triple:

```json
{
    "extra": {
        "mago-version": "1.29.0",
        "mago-sha256": {
            "x86_64-unknown-linux-musl": "5e99d1232fa93e6adc6feaaddaf2b46c148b2990173cdcf18400b474646bf046",
            "aarch64-apple-darwin": "…"
        }
    }
}
```

A stated checksum is only ever used for the version stated next to it, so a workflow that pins a
different `version` does not get it applied to the wrong archive. The `sha256` input wins over it.

None of that spends REST API quota. `latest` is read from where the releases page redirects to,
which names the tag, and a range is matched against `git ls-remote --tags`, which is the git
protocol. The REST API would answer the same questions out of the 1,000/hour budget every workflow
run in the repository shares.

That leaves anonymous requests, which GitHub counts against the runner's shared IP. `token` is
there for the one request where authenticating helps — the tag listing — and is unnecessary
otherwise: the release download and the `latest` redirect are not API calls and take no
credentials. A token GitHub rejects costs a warning and an anonymous retry, not the install.

Constraints are read as ranges: `^`, `~`, `x.y.*`, `>=`/`>`/`<=`/`<`/`=`, several of those side by
side, and `||` between alternatives. `!=` and hyphen ranges are not read — a constraint using them
resolves to the latest release with a warning.

Pinning the checksum is worth it where the version is pinned anyway:

```yaml
- uses: chaotic-ground/setup-mago@d79272ad1380980e87ff0c7da01b7131ccb0083b  # v1.1.0
  with:
    version: "1.29.0"
    sha256: "5e99d1232fa93e6adc6feaaddaf2b46c148b2990173cdcf18400b474646bf046"
```

The checksum is part of the cache key, so changing it forces a fresh download and a fresh
verification rather than handing back a binary an earlier, differently-pinned run had cached.

## Why this exists

Resolving a mago release through the GitHub REST API costs two calls per run — one to look up the
release by tag, one to list its assets — to arrive at a download URL that the pinned version
already determines. Those calls come out of the 1,000/hour `GITHUB_TOKEN` budget shared by every
workflow run in a repository, so a burst of pull requests can exhaust it and fail the job with a
403 that has nothing to do with the code under test.

This action constructs the asset URL directly and fetches it from the release CDN, which is not the
REST API, so it uses no quota. The binary is cached by target triple and version, so a hit skips
the download too.

It is a composite action on purpose: the work is `curl`, `tar`, a checksum and some shell to read a
version out of the composer files, none of which needs a JavaScript runtime, a bundled
`node_modules`, or the dependency-update churn that comes with one.

## Support

Linux and macOS on x86-64 and arm64, and Windows on x86-64 — every runner mago publishes an asset
for. mago has no arm64 Windows build, so an arm64 Windows runner is turned down with a clear error,
as is anything else, rather than being silently misdetected.

Reading a version out of composer files needs `jq`, which every GitHub-hosted runner image has. On
a self-hosted runner without it the read is skipped with a warning and the latest release is
installed, so pass `version` explicitly there.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
