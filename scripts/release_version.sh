#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-pubspec.yaml}"
base_version="$(sed -n 's/^version: \([^ +]*\).*/\1/p' "$manifest")"
release_version="$(sed -n 's/^release_version: \([^ #]*\).*/\1/p' "$manifest")"
if [[ -z "$base_version" ]]; then
  echo "Missing version in $manifest" >&2
  exit 1
fi
base_pattern="${base_version//./\\.}"
if [[ -n "$release_version" && "$release_version" != "$base_version" &&
      ! "$release_version" =~ ^${base_pattern}\.[0-9]+$ ]]; then
  echo "Release version must match $base_version or append a numeric hotfix." >&2
  exit 1
fi
printf '%s\n' "${release_version:-$base_version}"
