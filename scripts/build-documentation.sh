#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_directory="$repository_root/.build/documentation"
archive_directory="$output_directory/archives"
archive_path="$output_directory/TaskLoom-Documentation.zip"

mkdir -p "$output_directory"
rm -rf "$archive_directory"
rm -f "$archive_path"
mkdir -p "$archive_directory"

cd "$repository_root"
# Generate only TaskLoom's archive, rather than documenting dependency targets.
swift package --package-path "$repository_root" --allow-writing-to-directory "$archive_directory" \
    generate-documentation \
    --target TaskLoom \
    --output-path "$archive_directory/TaskLoom.doccarchive"

if [[ ! -d "$archive_directory/TaskLoom.doccarchive" ]]; then
    echo "Expected documentation archive was not generated: TaskLoom.doccarchive" >&2
    exit 1
fi

(
    cd "$archive_directory"
    zip -qry "$archive_path" TaskLoom.doccarchive
)

unzip -tq "$archive_path" >/dev/null
echo "Created $archive_path"
