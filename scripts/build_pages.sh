#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-}"
godot_version="${GODOT_VERSION:-4.5-stable}"
godot_version_dir="${GODOT_VERSION_DIR:-4.5.stable}"

download_file() {
	local url="$1"
	local output_path="$2"

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --retry 3 "$url" -o "$output_path"
		return
	fi

	if command -v wget >/dev/null 2>&1; then
		wget -q "$url" -O "$output_path"
		return
	fi

	echo "missing downloader: install curl or wget" >&2
	exit 1
}

install_godot_toolchain() {
	local tool_root="$HOME/.cache/pentris-pages/godot/$godot_version"
	local binary_path="$tool_root/godot4"
	local template_dir="$HOME/.local/share/godot/export_templates/$godot_version_dir"

	if [ -x "$binary_path" ] && [ -f "$template_dir/web_release.zip" ]; then
		godot_bin="$binary_path"
		return
	fi

	if ! command -v unzip >/dev/null 2>&1; then
		echo "missing dependency: unzip" >&2
		exit 1
	fi

	rm -rf "$tool_root"
	mkdir -p "$tool_root"
	mkdir -p "$template_dir"

	local godot_zip="/tmp/Godot_v${godot_version}_linux.x86_64.zip"
	local templates_tpz="/tmp/Godot_v${godot_version}_export_templates.tpz"

	download_file "https://github.com/godotengine/godot/releases/download/${godot_version}/Godot_v${godot_version}_linux.x86_64.zip" "$godot_zip"
	unzip -q "$godot_zip" -d "$tool_root"
	mv "$tool_root/Godot_v${godot_version}_linux.x86_64" "$binary_path"
	chmod +x "$binary_path"

	download_file "https://github.com/godotengine/godot/releases/download/${godot_version}/Godot_v${godot_version}_export_templates.tpz" "$templates_tpz"
	rm -rf "$template_dir"
	mkdir -p "$template_dir"
	unzip -q "$templates_tpz" -d "$template_dir"

	godot_bin="$binary_path"
}

if [ -z "$godot_bin" ]; then
	if command -v godot4 >/dev/null 2>&1; then
		godot_bin="$(command -v godot4)"
	else
		install_godot_toolchain
	fi
fi

cd "$repo_root"

"$godot_bin" --headless --path . -s res://tests/test_runner.gd
GODOT_BIN="$godot_bin" ./scripts/build_web.sh release build/web
