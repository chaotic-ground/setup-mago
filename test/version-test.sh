#!/usr/bin/env bash
# Exercises bin/version.sh without touching the network: "pick" is given a fixed release list and
# "detect" is given the composer files under test/fixtures. Run it directly to check a change.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
version_sh="$root/bin/version.sh"
failures=0

# A stand-in for the tag list git ls-remote returns, including shapes that must not be picked.
releases='0.6.2
0.7.0
1.0.0
1.28.0
1.29.0
1.30.1
2.0.0
2.1.0
v2.2.0
1.31.0-beta.1
nightly'

check() {
  got=$(printf '%s\n' "$releases" | "$version_sh" pick "$2" || true)
  if [ "$got" = "$3" ]; then
    echo "ok       pick $2 -> ${3:-<none>}"
  else
    echo "NOT OK   $1: pick $2 gave '${got:-<none>}', wanted '${3:-<none>}'"
    failures=$((failures + 1))
  fi
}

check "exact version" "1.29.0" "1.29.0"
check "exact version with a v" "v1.29.0" "1.29.0"
check "exact version nobody released" "1.29.9" ""
check "caret on a 1.x" "^1.28" "1.30.1"
check "caret pins the major" "^1.0.0" "1.30.1"
check "caret on a 0.x pins the minor" "^0.6.2" "0.6.2"
check "caret on a 0.x that has room" "^0.6" "0.6.2"
check "tilde with a patch pins the minor" "~1.29.0" "1.29.0"
check "tilde without a patch pins the major" "~1.29" "1.30.1"
check "x-range on the minor" "1.29.*" "1.29.0"
check "x-range on the major" "1.*" "1.30.1"
check "bare partial reads as an x-range" "1.30" "1.30.1"
check "wildcard" "*" "2.2.0"
check "greater or equal" ">=1.30" "2.2.0"
check "bounded range" ">=1.0 <2.0" "1.30.1"
check "comma is an and" ">=1.0,<1.29" "1.28.0"
check "alternatives" "^0.7 || ^1.0" "1.30.1"
# A hyphen range and != are the two shapes the window model does not read; both end up
# unresolved, and the action falls back to the latest release with a warning rather than guessing.
check "hyphen range is not read" "1.0.0 - 1.29.0" ""
check "not equal is not read" "1.30.* !=1.30.1" ""
check "nothing satisfiable" "^9.0" ""
check "not a constraint at all" "dev-main" ""

# Prereleases and non-version tags must never win, whatever is asked for.
check "prereleases are not offered" ">=1.31.0 <2.0.0" ""

detects() {
  got=$("$version_sh" detect "$root/test/fixtures/$2")
  if [ "$got" = "$3" ]; then
    echo "ok       detect $2 -> ${3:-<none>}"
  else
    echo "NOT OK   $1: detect $2 gave '${got:-<none>}', wanted '${3:-<none>}'"
    failures=$((failures + 1))
  fi
}

detects "a version stated in extra" extra "1.29.0"
detects "extra wins over the lockfile" extra-and-lockfile "1.29.0"
detects "lockfile wins over the manifest" lockfile "1.29.0"
detects "manifest range when there is no lockfile" manifest "^1.29"
detects "manifest exact version" manifest-exact "1.29.0"
detects "mago in require rather than require-dev" manifest-require "1.29.0"
detects "a project that does not use mago" no-mago ""
detects "a directory with no composer files" ../.. ""

# A checksum belongs to one archive, so it is only offered for the version stated beside it and
# for the platform it was written for.
linux=x86_64-unknown-linux-musl
sha=5e99d1232fa93e6adc6feaaddaf2b46c148b2990173cdcf18400b474646bf046
zeros=0000000000000000000000000000000000000000000000000000000000000000

states() {
  got=$("$version_sh" checksum "$root/test/fixtures/$2" "$3" "$4")
  if [ "$got" = "$5" ]; then
    echo "ok       checksum $2 $3 $4 -> ${5:-<none>}"
  else
    echo "NOT OK   $1: checksum $2 $3 $4 gave '${got:-<none>}', wanted '${5:-<none>}'"
    failures=$((failures + 1))
  fi
}

states "a checksum stated as one value" extra "$linux" 1.29.0 "$sha"
states "not for a version nobody stated" extra "$linux" 1.30.0 ""
states "a checksum stated per platform" extra-map "$linux" 1.29.0 "$sha"
states "the entry for the other platform" extra-map aarch64-apple-darwin 1.29.0 "$zeros"
states "no entry for this platform" extra-map aarch64-pc-windows-msvc 1.29.0 ""
states "a project that states no checksum" extra-and-lockfile "$linux" 1.29.0 ""
states "a project that states nothing" no-mago "$linux" 1.29.0 ""

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
