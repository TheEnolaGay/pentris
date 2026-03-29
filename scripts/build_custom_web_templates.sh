#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-tools/godot-export-templates/4.5.stable}"
godot_ref="${GODOT_REF:-4.5-stable}"
godot_version_dir="${GODOT_VERSION_DIR:-4.5.stable}"
source_dir="${GODOT_SOURCE_DIR:-$HOME/.cache/pentris-pages/godot-source/${godot_ref}}"
profile_path="$repo_root/scripts/godot_web_size_profile.py"
jobs="${SCONS_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

require_command() {
	local command_name="$1"

	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "missing dependency: $command_name" >&2
		exit 1
	fi
}

prepare_source() {
	if [ -d "$source_dir/.git" ]; then
		git -C "$source_dir" fetch --depth 1 origin "$godot_ref"
		git -C "$source_dir" checkout --force FETCH_HEAD
		return
	fi

	rm -rf "$source_dir"
	mkdir -p "$(dirname "$source_dir")"
	git clone --depth 1 --branch "$godot_ref" https://github.com/godotengine/godot.git "$source_dir"
}

find_built_template() {
	local pattern="$1"
	find "$source_dir/bin" -maxdepth 1 -type f -name "$pattern" | head -n 1
}

build_template() {
	local target="$1"

	scons -C "$source_dir" \
		platform=web \
		target="$target" \
		threads=no \
		profile="$profile_path" \
		-j"$jobs"
}

package_templates() {
	local release_zip="$1"
	local debug_zip="$2"

	rm -rf "$output_dir"
	mkdir -p "$output_dir"

	cp "$release_zip" "$output_dir/web_nothreads_release.zip"
	cp "$debug_zip" "$output_dir/web_nothreads_debug.zip"
	printf '%s\n' "$godot_version_dir" > "$output_dir/version.txt"

	printf '%s\n' "$output_dir/web_nothreads_release.zip"
	printf '%s\n' "$output_dir/web_nothreads_debug.zip"
}

require_command git
require_command python3
require_command scons
require_command emcc

prepare_source

build_template template_release
build_template template_debug

release_zip="$(find_built_template 'godot.web.template_release.wasm32*.zip')"
debug_zip="$(find_built_template 'godot.web.template_debug.wasm32*.zip')"

if [ -z "$release_zip" ] || [ -z "$debug_zip" ]; then
	echo "failed to locate built web template zips under $source_dir/bin" >&2
	exit 1
fi

package_templates "$release_zip" "$debug_zip"
