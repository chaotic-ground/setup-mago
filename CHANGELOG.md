# Changelog

## [1.1.0](https://github.com/chaotic-ground/setup-mago/compare/v1.0.0...v1.1.0) (2026-08-15)


### Features

* take the version and checksum from composer.json's extra ([#7](https://github.com/chaotic-ground/setup-mago/issues/7)) ([f77c462](https://github.com/chaotic-ground/setup-mago/commit/f77c462281ec810877c4b8a7e5ba6099ccb32441))


### Bugfixes

* turn down arm64 Windows instead of fetching an asset that does not exist ([#6](https://github.com/chaotic-ground/setup-mago/issues/6)) ([465b927](https://github.com/chaotic-ground/setup-mago/commit/465b92782772e7a37de494f80cef155e8be5f755))

## 1.0.0 (2026-08-15)


### Features

* accept "latest" and report the installed version ([a811c80](https://github.com/chaotic-ground/setup-mago/commit/a811c8023ece38c00009d70d16869a335f2fa7b2))
* composite action installing mago without GitHub REST calls ([4042602](https://github.com/chaotic-ground/setup-mago/commit/4042602ce52a1108688c4009734eedba2a9b66e4))
* read the version from composer files, and support Windows ([#5](https://github.com/chaotic-ground/setup-mago/issues/5)) ([6a79082](https://github.com/chaotic-ground/setup-mago/commit/6a7908222c3180f60712129401d74fb3f644d307))


### Bugfixes

* stop a cache entry standing in for a checksum that never passed ([ec214f5](https://github.com/chaotic-ground/setup-mago/commit/ec214f561bca698815040aedac67b0a0af466dcd))
