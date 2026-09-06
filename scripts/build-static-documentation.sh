#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_directory="$repository_root/.build/site"

usage() {
    echo "Usage: $0 [--output-directory DIRECTORY]" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-directory)
            [[ $# -ge 2 ]] || { usage; exit 1; }
            output_directory="$2"
            shift 2
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

mkdir -p "$output_directory/api"
output_directory="$(cd "$output_directory" && pwd)"

modules=(
    "TaskLoom:taskloom"
)

for module in "${modules[@]}"; do
    target="${module%%:*}"
    route_name="${module##*:}"
    destination="$output_directory/api/$route_name"

    rm -rf "$destination"
    mkdir -p "$destination"

    swift package --package-path "$repository_root" --allow-writing-to-directory "$destination" \
        generate-documentation \
        --target "$target" \
        --output-path "$destination" \
        --transform-for-static-hosting \
        --hosting-base-path "docs/taskloom-swift/api/$route_name"
done

echo "Created static DocC sites in $output_directory/api"
