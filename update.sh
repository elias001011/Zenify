#!/usr/bin/env bash
set -euo pipefail

version="$(bash scripts/release_version.sh)"
printf "const appVersion = '%s';\n" "$version" > lib/constants/version.dart
