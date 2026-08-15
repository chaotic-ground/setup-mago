# setup-mago

Installs the [mago](https://github.com/carthage-software/mago) PHP toolchain in GitHub Actions.

```yaml
- uses: chaotic-ground/setup-mago@4042602ce52a1108688c4009734eedba2a9b66e4  # v1.0.0
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
| `version` | `latest` | Version to install, without a leading `v` (e.g. `1.29.0`), or `latest`. |
| `sha256` | — | Expected sha256 of the release archive. Verified before install when set. |

| Output | Description |
|---|---|
| `version` | The version installed, with `latest` resolved to a concrete one. |

`latest` is resolved from where the releases page redirects to, which names the tag. Asking the
REST API instead would spend the quota this action exists to protect — and more of it than a pinned
version does, since resolving latest there means listing every release.

Pinning the checksum is worth it where the version is pinned anyway:

```yaml
- uses: chaotic-ground/setup-mago@4042602ce52a1108688c4009734eedba2a9b66e4  # v1.0.0
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

It is a composite action on purpose: the work is `curl`, `tar` and a checksum, none of which needs
a JavaScript runtime, a bundled `node_modules`, or the dependency-update churn that comes with one.

## Support

Linux and macOS, on x86-64 and arm64. Windows runners are rejected with a clear error rather than
silently misdetected; mago does publish a Windows asset, so adding it is mostly a matter of
handling the `.zip` and the `.exe` suffix if someone needs it.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).
