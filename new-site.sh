#!/bin/sh
# Scaffolds (or migrates) a static site repo onto static-site-kit.
#
# Usage: new-site.sh <site-dir> [--name <service>] [--domain <domain>]
#                    [--image ghcr.io/<owner>/<repo>] [--force]
#
#   --name    Compose service/container name. Default: directory name,
#             lowercased, with _ replaced by -.
#   --domain  Public domain(s), recorded in deploy/homelab.md.
#   --image   Default: derived from the repo's GitHub origin remote.
#   --force   Overwrite existing files (site/ is never overwritten).
#
# Existing files are skipped unless --force; site/index.html is only created
# when site/ doesn't exist yet.
set -eu

KIT_REPO="${KIT_REPO:-3awaref/static-site-kit}"
KIT_MAJOR=1
kit_dir=$(cd "$(dirname "$0")" && pwd)

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-1}"; }
die() { echo "new-site: $*" >&2; exit 1; }

[ $# -ge 1 ] || usage
case "$1" in -h | --help) usage 0 ;; esac
dir="$1"
shift
name="" domain="" image="" force=0
while [ $# -gt 0 ]; do
    case "$1" in
        --name) name="${2:?--name needs a value}"; shift 2 ;;
        --domain) domain="${2:?--domain needs a value}"; shift 2 ;;
        --image) image="${2:?--image needs a value}"; shift 2 ;;
        --force) force=1; shift ;;
        -h | --help) usage 0 ;;
        *) die "unknown option $1" ;;
    esac
done

mkdir -p "$dir"
dir=$(cd "$dir" && pwd)

[ -n "$name" ] || name=$(basename "$dir" | tr 'A-Z_' 'a-z-')
echo "$name" | grep -Eq '^[a-z0-9][a-z0-9-]*$' \
    || die "service name '$name' must be lowercase letters, digits and -"

unresolved=""
if [ -z "$image" ]; then
    remote=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
    repo=$(printf '%s\n' "$remote" | sed -nE 's#^(git@github\.com:|https://github\.com/)([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//')
    if [ -n "$repo" ]; then
        image="ghcr.io/$repo"
    else
        image="ghcr.io/OWNER/REPO"
        unresolved="$unresolved image"
    fi
fi
image=$(printf '%s' "$image" | tr 'A-Z' 'a-z')
if [ -z "$domain" ]; then
    domain="Unresolved: domain to be supplied"
    unresolved="$unresolved domain"
fi
base="ghcr.io/$(printf '%s' "$KIT_REPO" | tr 'A-Z' 'a-z'):$KIT_MAJOR"

# Escape for the right-hand side of a sed s||| command.
esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

cd "$kit_dir/templates"
find . -type f | sed 's#^\./##' | sort | while IFS= read -r rel; do
    dest="$dir/$rel"
    case "$rel" in
        site/*) [ -e "$dir/site" ] && continue ;;
        *) if [ -e "$dest" ] && [ "$force" -eq 0 ]; then
               echo "skip     $rel (exists; --force to overwrite)"
               continue
           fi ;;
    esac
    mkdir -p "$(dirname "$dest")"
    sed -e "s|@@NAME@@|$(esc "$name")|g" \
        -e "s|@@IMAGE@@|$(esc "$image")|g" \
        -e "s|@@DOMAIN@@|$(esc "$domain")|g" \
        -e "s|@@KIT@@|$(esc "$KIT_REPO")|g" \
        -e "s|@@BASE@@|$(esc "$base")|g" \
        "$rel" > "$dest"
    echo "write    $rel"
done

echo
echo "service: $name"
echo "image:   $image"
echo "base:    $base"
[ -z "$unresolved" ] || echo "unresolved:$unresolved (fill in deploy/homelab.compose.yml / deploy/homelab.md)"
