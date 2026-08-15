#!/usr/bin/env bash
# Works out which mago version to install.
#
# The answer is whatever the project already states -- a version in composer.lock, a version or a
# range in composer.json -- and a range needs the list of releases to choose from. That list comes
# from "git ls-remote --tags", which is the git protocol rather than the REST API and so costs none
# of the repository's hourly quota; asking the API to list releases is what this action avoids.
#
#   version.sh detect <dir>     print the mago constraint the composer files ask for, if any
#   version.sh checksum <dir> <triple> <version>
#                               print the sha256 the composer files state for that archive, if any
#   version.sh pick <spec>      print the newest version on stdin that satisfies <spec>
#   version.sh resolve <spec>   print the concrete version <spec> means, consulting the network
#
# Kept to constructs bash 3.2 has, since that is what macOS runners ship.
set -euo pipefail
# A constraint is full of characters the shell would otherwise read as a glob.
set -f

MAGO_REPO=${MAGO_REPO:-https://github.com/carthage-software/mago}
PACKAGE=carthage-software/mago

# Every constraint here is one or more half-open windows: "^1.29" is [1.29.0, 2.0.0) and
# ">=1.0 <1.5" is [1.0.0, 1.5.0). A version then only ever has to be compared with a window edge,
# which is easier on a padded key -- 1.29.0 becomes 000001000029000000, one number to compare --
# than on three numbers in sequence.
FLOOR=000000000000000000
CEILING=999999999999999999

warn() { echo "::warning::$*" >&2; }

# The key for a version, and nothing at all for something that is not one ("dev-main", "-").
key() {
  _k=${1#v}
  _k=${_k%%-*}
  _k=${_k%%+*}
  case "$_k" in
    '' | .* | *[!0-9.]*) return 1 ;;
  esac
  _major=${_k%%.*}
  _rest=${_k#*.}
  if [ "$_rest" = "$_k" ]; then _rest=0.0; fi
  _minor=${_rest%%.*}
  _patch=${_rest#*.}
  if [ "$_patch" = "$_rest" ]; then _patch=0; fi
  _patch=${_patch%%.*}
  printf '%06d%06d%06d\n' "${_major:-0}" "${_minor:-0}" "${_patch:-0}"
}

unkey() {
  printf '%d.%d.%d\n' "$((10#${1:0:6}))" "$((10#${1:6:6}))" "$((10#${1:12:6}))"
}

# The next key up at the given level, which is where a window ends: after 1.29.x comes 1.30.0,
# after 1.x comes 2.0.0.
next() {
  _major=$((10#${1:0:6}))
  _minor=$((10#${1:6:6}))
  _patch=$((10#${1:12:6}))
  case "$2" in
    major) _major=$((_major + 1)); _minor=0; _patch=0 ;;
    minor) _minor=$((_minor + 1)); _patch=0 ;;
    patch) _patch=$((_patch + 1)) ;;
  esac
  printf '%06d%06d%06d\n' "$_major" "$_minor" "$_patch"
}

# One comparator as "<low> <high>". A shape this does not read -- "!=1.0", a hyphen range -- fails,
# and the caller treats that as "cannot tell" rather than guessing a window.
bound() {
  case "$1" in
    '' | '*') printf '%s %s\n' "$FLOOR" "$CEILING"; return 0 ;;
  esac
  _op=$(printf '%s' "$1" | sed 's/[^^~><=].*//')
  _operand=${1#"$_op"}
  # "1.29.*" covers the same releases as "1.29", so drop the wildcard and count what is left.
  case "$_operand" in *.\*) _operand=${_operand%.\*} ;; esac
  case "$_operand" in
    *.*.*) _given=3 ;;
    *.*) _given=2 ;;
    *) _given=1 ;;
  esac
  _low=$(key "$_operand") || return 1
  # Most comparators are "from here up to the next X", and differ only in which X: the operator
  # and how many numbers were written decide the level, and one step up from there closes it.
  _level=
  case "$_op" in
    '>=') _high=$CEILING ;;
    '>') _low=$(next "$_low" patch); _high=$CEILING ;;
    '<') _high=$_low; _low=$FLOOR ;;
    '<=') _high=$(next "$_low" patch); _low=$FLOOR ;;
    # Caret keeps the leftmost non-zero number, so 0.x releases break on the minor and 0.0.x on
    # the patch -- composer's reading of it, not npm's.
    '^') case "$_low" in
      000000000000*) _level="patch" ;;
      000000*) _level="minor" ;;
      *) _level="major" ;;
    esac ;;
    # A tilde frees the last number that was given: ~1.29.0 is 1.29.x, ~1.29 is 1.x.
    '~') if [ "$_given" -ge 3 ]; then _level="minor"; else _level="major"; fi ;;
    # A bare version is exact when all three numbers are there, and a range when they are not.
    '' | '=') case "$_given" in
      3) _level="patch" ;;
      2) _level="minor" ;;
      *) _level="major" ;;
    esac ;;
    *) return 1 ;;
  esac
  if [ -n "$_level" ]; then _high=$(next "$_low" "$_level"); fi
  printf '%s %s\n' "$_low" "$_high"
}

# Comparators written side by side all have to hold, so their window is where they overlap.
window() {
  _low=$FLOOR
  _high=$CEILING
  for _comparator in $(printf '%s' "$1" | tr ',' ' '); do
    _bound=$(bound "$_comparator") || return 1
    _bound_low=${_bound% *}
    _bound_high=${_bound#* }
    if ((10#$_bound_low > 10#$_low)); then _low=$_bound_low; fi
    if ((10#$_bound_high < 10#$_high)); then _high=$_bound_high; fi
  done
  printf '%s %s\n' "$_low" "$_high"
}

# Newest version on stdin inside any window the spec allows. Prereleases and tags that are not
# versions are never offered: a constraint in a composer file is about released versions.
pick() {
  _windows=
  _spec=$(printf '%s' "$1" | sed 's/||/|/g')
  while [ -n "$_spec" ]; do
    case "$_spec" in
      *'|'*) _alternative=${_spec%%|*}; _spec=${_spec#*|} ;;
      *) _alternative=$_spec; _spec= ;;
    esac
    _windows="$_windows$(window "$_alternative" || true)
"
  done
  _best=
  while read -r _candidate; do
    case "${_candidate#v}" in
      *[!0-9.]*) continue ;;
      [0-9]*.[0-9]*.[0-9]*) ;;
      *) continue ;;
    esac
    _key=$(key "$_candidate") || continue
    while read -r _low _high; do
      [ -n "$_high" ] || continue
      if ((10#$_key < 10#$_low || 10#$_key >= 10#$_high)); then continue; fi
      if [ -z "$_best" ] || ((10#$_key > 10#$_best)); then _best=$_key; fi
    done <<EOF
$_windows
EOF
  done
  if [ -n "$_best" ]; then unkey "$_best"; fi
}

# The version the project already states. "extra" comes first: a project that installs mago from
# its release archive rather than through composer has nowhere else to put the version, and saying
# it there is a statement about the binary, where the lockfile entry is about the package.
detect() {
  _root=$1
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is not installed, so composer.lock and composer.json cannot be read for a mago version"
    return 0
  fi
  if [ -f "$_root/composer.json" ]; then
    _stated=$(jq -r '.extra["mago-version"] // empty' "$_root/composer.json" 2>/dev/null || true)
    if [ -n "$_stated" ]; then printf '%s\n' "$_stated"; return 0; fi
  fi
  if [ -f "$_root/composer.lock" ]; then
    _locked=$(jq -r --arg p "$PACKAGE" \
      '[(.["packages-dev"] // [])[], (.packages // [])[]] | map(select(.name == $p)) | .[0].version // empty' \
      "$_root/composer.lock" 2>/dev/null || true)
    if [ -n "$_locked" ]; then printf '%s\n' "$_locked"; return 0; fi
  fi
  if [ -f "$_root/composer.json" ]; then
    _required=$(jq -r --arg p "$PACKAGE" \
      '(.["require-dev"] // {})[$p] // (.require // {})[$p] // empty' \
      "$_root/composer.json" 2>/dev/null || true)
    if [ -n "$_required" ]; then printf '%s\n' "$_required"; return 0; fi
  fi
  return 0
}

# The checksum the project states for the archive, if it states one, and only for the version it
# stated alongside it: a checksum belongs to one archive, so it must not be carried over to a
# version somebody else chose. The value is per-platform, so an object keyed by target triple is
# the honest form; a bare string is taken as given, which is right for a project that installs on
# one platform and fails loudly rather than quietly on another.
checksum() {
  _root=$1
  _triple=$2
  _version=$3
  if ! command -v jq >/dev/null 2>&1; then return 0; fi
  if [ ! -f "$_root/composer.json" ]; then return 0; fi
  _stated=$(jq -r '.extra["mago-version"] // empty' "$_root/composer.json" 2>/dev/null || true)
  if [ "${_stated#v}" != "$_version" ]; then return 0; fi
  jq -r --arg t "$_triple" \
    '(.extra["mago-sha256"] // empty) as $s
     | if ($s | type) == "object" then ($s[$t] // empty) else $s end' \
    "$_root/composer.json" 2>/dev/null || true
}

# The tag list is the one request a token can help with: git counts an authenticated request
# against the account rather than against the runner's shared IP. It is passed through the
# environment rather than the command line so it stays out of the process list, and a token the
# server rejects costs a warning and an anonymous retry rather than the whole resolution.
tags() {
  if [ -n "${MAGO_TOKEN:-}" ]; then
    _basic=$(printf 'x-access-token:%s' "$MAGO_TOKEN" | base64 | tr -d '\n')
    if _refs=$(GIT_CONFIG_COUNT=1 \
      GIT_CONFIG_KEY_0=http.extraheader \
      GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $_basic" \
      git ls-remote --tags --refs "$MAGO_REPO" 2>/dev/null); then
      printf '%s\n' "$_refs" | sed 's#.*refs/tags/##'
      return 0
    fi
    warn "the token was not accepted for listing mago's tags; asking again without it"
  fi
  git ls-remote --tags --refs "$MAGO_REPO" | sed 's#.*refs/tags/##'
}

latest() {
  # Where the releases page redirects to names the tag. The REST API would answer the same thing
  # by listing every release, which is the quota this action exists to protect.
  _effective=$(curl -fsSLo /dev/null -w '%{url_effective}' "$MAGO_REPO/releases/latest")
  _tag=${_effective##*/}
  if [ -z "$_tag" ] || [ "$_tag" = latest ]; then
    echo "::error::could not resolve the latest mago release; the redirect gave $_effective" >&2
    return 1
  fi
  printf '%s\n' "${_tag#v}"
}

resolve() {
  case "$1" in
    '' | latest) latest; return ;;
  esac
  # A concrete version is the answer already, and asking the network could only confirm it.
  case "${1#v}" in
    [0-9]*.[0-9]*.[0-9]*)
      case "${1#v}" in
        *[!0-9.]*) ;;
        *) printf '%s\n' "${1#v}"; return ;;
      esac
      ;;
  esac
  _resolved=$(tags | pick "$1" || true)
  if [ -z "$_resolved" ]; then
    warn "no mago release satisfies \"$1\"; installing the latest release instead"
    latest
    return
  fi
  printf '%s\n' "$_resolved"
}

case "${1:-}" in
  detect) detect "${2:-$PWD}" ;;
  checksum) checksum "${2:-$PWD}" "${3:-}" "${4:-}" ;;
  pick) pick "${2:-}" ;;
  resolve) resolve "${2:-}" ;;
  *)
    echo "usage: version.sh detect <dir> | checksum <dir> <triple> <version> | pick <spec> | resolve <spec>" >&2
    exit 2
    ;;
esac
