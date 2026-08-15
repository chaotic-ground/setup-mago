#!/usr/bin/env bash
# Works out which mago version to install.
#
# The answer is whatever the project already states -- a version in composer.lock, a version or a
# range in composer.json -- and a range needs the list of releases to choose from. That list comes
# from "git ls-remote --tags", which is the git protocol rather than the REST API and so costs none
# of the repository's hourly quota; asking the API to list releases is what this action avoids.
#
#   version.sh detect <dir>     print the mago constraint the composer files ask for, if any
#   version.sh pick <spec>      print the newest version on stdin that satisfies <spec>
#   version.sh resolve <spec>   print the concrete version <spec> means, consulting the network
#
# Kept to constructs bash 3.2 has, since that is what macOS runners ship.
set -euo pipefail
# A constraint is full of characters the shell would otherwise read as a glob.
set -f

MAGO_REPO=${MAGO_REPO:-https://github.com/carthage-software/mago}
PACKAGE=carthage-software/mago

warn() { echo "::warning::$*" >&2; }

# Only "1", "1.2", "v1.2.3" and the like are versions; "dev-main" and friends are not.
numeric() {
  _n=${1#v}
  _n=${_n%%-*}
  _n=${_n%%+*}
  case "$_n" in
    '' | *[!0-9.]*) return 1 ;;
    [0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

# "v1.2" -> "1.2.0". Anything after the three numbers (prerelease, build metadata) is dropped:
# mago releases are plain X.Y.Z, and a constraint is only ever compared against those.
normalize() {
  _v=${1#v}
  _v=${_v%%-*}
  _v=${_v%%+*}
  _major=${_v%%.*}
  _rest=${_v#*.}
  if [ "$_rest" = "$_v" ]; then _rest="0.0"; fi
  _minor=${_rest%%.*}
  _patch=${_rest#*.}
  if [ "$_patch" = "$_rest" ]; then _patch=0; fi
  _patch=${_patch%%.*}
  printf '%s.%s.%s\n' "${_major:-0}" "${_minor:-0}" "${_patch:-0}"
}

# How many numbers the constraint actually named, which is what tells "~1.2" from "~1.2.0".
components() {
  _c=${1#v}
  _c=${_c%%-*}
  case "$_c" in
    *.*.*) echo 3 ;;
    *.*) echo 2 ;;
    *) echo 1 ;;
  esac
}

# -1, 0 or 1, comparing the three numbers in order.
vcmp() {
  _a=$(normalize "$1")
  _b=$(normalize "$2")
  while [ -n "$_a$_b" ]; do
    _x=${_a%%.*}
    _y=${_b%%.*}
    if [ "${_x:-0}" -lt "${_y:-0}" ]; then echo -1; return; fi
    if [ "${_x:-0}" -gt "${_y:-0}" ]; then echo 1; return; fi
    case "$_a" in *.*) _a=${_a#*.} ;; *) _a= ;; esac
    case "$_b" in *.*) _b=${_b#*.} ;; *) _b= ;; esac
  done
  echo 0
}

bump() {
  _b=$(normalize "$1")
  case "$2" in
    major) printf '%s.0.0\n' "$((${_b%%.*} + 1))" ;;
    minor) _t=${_b#*.}; printf '%s.%s.0\n' "${_b%%.*}" "$((${_t%%.*} + 1))" ;;
    patch) _t=${_b#*.}; printf '%s.%s.%s\n' "${_b%%.*}" "${_t%%.*}" "$((${_t#*.} + 1))" ;;
  esac
}

# Turns one comparator into "<op> <version>" lines: everything downstream compares versions only.
expand() {
  case "$1" in
    '' | '*') ;;
    '>='* | '<='* | '!='* | '>'* | '<'* | '='*)
      numeric "$(printf '%s' "$1" | sed 's/^[><=!]*//')" || return 0
      ;;
    *)
      numeric "$(printf '%s' "$1" | sed 's/^[\^~]//;s/\.\*$//')" || return 0
      ;;
  esac
  case "$1" in
    '' | '*') echo ">= 0.0.0" ;;
    ^*)
      _base=$(normalize "${1#^}")
      echo ">= $_base"
      # Caret keeps the leftmost non-zero number, so 0.x releases are breaking on the minor and
      # 0.0.x on the patch -- composer's reading of it, not npm's.
      case "$_base" in
        0.0.*) echo "< $(bump "$_base" patch)" ;;
        0.*) echo "< $(bump "$_base" minor)" ;;
        *) echo "< $(bump "$_base" major)" ;;
      esac
      ;;
    ~*)
      _base=$(normalize "${1#\~}")
      echo ">= $_base"
      if [ "$(components "${1#\~}")" -ge 3 ]; then
        echo "< $(bump "$_base" minor)"
      else
        echo "< $(bump "$_base" major)"
      fi
      ;;
    *.\*)
      _base=$(normalize "${1%.\*}")
      echo ">= $_base"
      if [ "$(components "${1%.\*}")" -ge 2 ]; then
        echo "< $(bump "$_base" minor)"
      else
        echo "< $(bump "$_base" major)"
      fi
      ;;
    '>='* | '<='* | '!='* | '>'* | '<'* | '='*)
      _op=$(printf '%s' "$1" | sed 's/[^><=!].*//')
      echo "$_op $(normalize "${1#"$_op"}")"
      ;;
    *)
      # A bare version: exact when all three numbers are given, otherwise the range they cover.
      if [ "$(components "$1")" -ge 3 ]; then
        echo "= $(normalize "$1")"
      else
        expand "$1.*"
      fi
      ;;
  esac
}

satisfies_one() {
  _cmp=$(vcmp "$3" "$2")
  case "$1" in
    '>=') [ "$_cmp" -ge 0 ] ;;
    '>') [ "$_cmp" -gt 0 ] ;;
    '<=') [ "$_cmp" -le 0 ] ;;
    '<') [ "$_cmp" -lt 0 ] ;;
    '!=') [ "$_cmp" -ne 0 ] ;;
    *) [ "$_cmp" -eq 0 ] ;;
  esac
}

# All comparators in one alternative must hold; a hyphen range is the pair they stand for.
satisfies_alternative() {
  _alt=$(printf '%s' "$1" | tr ',' ' ')
  _version=$2
  case " $_alt " in
    *' - '*)
      _low=${_alt%% - *}
      _high=${_alt##* - }
      _alt=">=$_low"
      if [ "$(components "$_high")" -ge 3 ]; then
        _alt="$_alt <=$_high"
      else
        _alt="$_alt <$(bump "$_high" minor)"
      fi
      ;;
  esac
  for _comparator in $_alt; do
    _predicates=$(expand "$_comparator")
    [ -n "$_predicates" ] || return 1
    _held=yes
    while read -r _op _ref; do
      [ -n "$_op" ] || continue
      if ! satisfies_one "$_op" "$_ref" "$_version"; then _held=no; break; fi
    done <<EOF
$_predicates
EOF
    [ "$_held" = yes ] || return 1
  done
  return 0
}

satisfies() {
  _spec=$(printf '%s' "$1" | sed 's/||/|/g')
  _version=$2
  _rest=$_spec
  while [ -n "$_rest" ]; do
    case "$_rest" in
      *'|'*) _alternative=${_rest%%|*}; _rest=${_rest#*|} ;;
      *) _alternative=$_rest; _rest= ;;
    esac
    if satisfies_alternative "$_alternative" "$_version"; then return 0; fi
  done
  return 1
}

# Newest version on stdin that the spec accepts. Prereleases and tags that are not versions are
# never offered: a constraint in a composer file is about released versions.
pick() {
  _best=
  while read -r _candidate; do
    case "$_candidate" in
      v[0-9]*.[0-9]*.[0-9]* | [0-9]*.[0-9]*.[0-9]*) ;;
      *) continue ;;
    esac
    case "${_candidate#v}" in
      *[!0-9.]*) continue ;;
    esac
    satisfies "$1" "$_candidate" || continue
    if [ -z "$_best" ] || [ "$(vcmp "$_candidate" "$_best")" -gt 0 ]; then
      _best=$(normalize "$_candidate")
    fi
  done
  if [ -n "$_best" ]; then printf '%s\n' "$_best"; fi
}

# The constraint the project already states: the lockfile first, since it pins one version, then
# the manifest, which may instead name a range.
detect() {
  _root=$1
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq is not installed, so composer.lock and composer.json cannot be read for a mago version"
    return 0
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

tags() {
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
  pick) pick "${2:-}" ;;
  resolve) resolve "${2:-}" ;;
  *)
    echo "usage: version.sh detect <dir> | pick <spec> | resolve <spec>" >&2
    exit 2
    ;;
esac
