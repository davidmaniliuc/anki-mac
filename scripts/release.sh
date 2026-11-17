#!/usr/bin/env bash
# Tags HEAD as the next release and pushes the tag, which is what publishes
# it (.github/workflows/release.yml, docs/RELEASING.md).
#
#     scripts/release.sh            next patch: v0.1.0 first, then v0.1.1, ...
#     scripts/release.sh 0.2        start a new series at v0.2.0
#     scripts/release.sh 1.0.0      exactly this version
#
# Nothing is pushed until the tag is confirmed.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "error: $*" >&2; exit 1; }

[ "$(git rev-parse --abbrev-ref HEAD)" = master ] || fail "releases are cut from master"
[ -z "$(git status --porcelain --untracked-files=no)" ] || fail "the working tree has uncommitted changes"
git fetch -q --tags origin master
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] \
  || fail "HEAD is not origin/master; push (or pull) first, so the tag names a commit GitHub has"
if tag=$(git describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null); then
  fail "HEAD is already released as $tag"
fi

latest=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -1)
latest=${latest#v}

case "${1:-}" in
  "")
    if [ -n "$latest" ]; then
      version="${latest%.*}.$(( ${latest##*.} + 1 ))"
    else
      version=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' App/project.yml | head -1)
    fi
    ;;
  *.*.*) version=$1 ;;
  *.*) version=$1.0 ;;
  *) fail "give a series (0.2) or a version (1.0.0), not '$1'" ;;
esac

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "'$version' is not MAJOR.MINOR.PATCH"
git rev-parse -q --verify "refs/tags/v$version" >/dev/null && fail "v$version already exists"
if [ -n "$latest" ] && [ "$(printf '%s\n%s\n' "$latest" "$version" | sort -V | tail -1)" != "$version" ]; then
  fail "v$version would sort before the latest release, v$latest"
fi

echo "Release AnkiMac $version (build $(git rev-list --count HEAD), $(git rev-parse --short=7 HEAD)): $(git log -1 --format=%s | cut -c1-100)"
read -r -p "Tag v$version and push it? [y/N] " answer
[ "$answer" = y ] || [ "$answer" = Y ] || fail "nothing tagged"

git tag -a "v$version" -m "AnkiMac $version"
git push origin "v$version"
echo "pushed v$version; the release workflow is building it:"
echo "    https://github.com/davidmaniliuc/anki-mac/actions/workflows/release.yml"
