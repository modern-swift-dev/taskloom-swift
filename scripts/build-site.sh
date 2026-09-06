#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
website_directory="$repository_root/Website"
astro_output_directory="$website_directory/dist"
build_directory="$repository_root/.build"
published_directory="$build_directory/site"

mkdir -p "$build_directory"
staging_directory="$(mktemp -d "$build_directory/site.XXXXXX")"

cleanup() {
    rm -rf "$staging_directory"
}
trap cleanup EXIT

if [[ ! -d "$website_directory/node_modules" ]]; then
    echo "Website dependencies are missing. Run 'make site-setup' first." >&2
    exit 1
fi

if [[ ! -f "$website_directory/package.json" ]]; then
    echo "Missing Website/package.json." >&2
    exit 1
fi

npm run build --prefix "$website_directory"

if [[ ! -d "$astro_output_directory" ]]; then
    echo "Astro did not create $astro_output_directory." >&2
    exit 1
fi

cp -R "$astro_output_directory/." "$staging_directory"
printf '\n' > "$staging_directory/.nojekyll"

bash "$repository_root/scripts/build-static-documentation.sh" \
    --output-directory "$staging_directory"
node "$website_directory/scripts/check-internal-links.mjs" "$staging_directory"

rm -rf "$published_directory"
mv "$staging_directory" "$published_directory"
trap - EXIT

echo "Created $published_directory"
