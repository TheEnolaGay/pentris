#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot_bin="${GODOT_BIN:-}"
godot_version="${GODOT_VERSION:-4.5-stable}"
godot_version_dir="${GODOT_VERSION_DIR:-4.5.stable}"
template_dir="$HOME/.local/share/godot/export_templates/$godot_version_dir"
template_repo="${PENTRIS_TEMPLATE_REPO:-TheEnolaGay/pentris}"
template_tag="${PENTRIS_TEMPLATE_TAG:-godot-web-template-4.5-stable-pentris-v1}"
template_asset="${PENTRIS_TEMPLATE_ASSET:-pentris-godot-web-templates-${template_tag}.tar.gz}"
template_checksum_asset="${PENTRIS_TEMPLATE_CHECKSUM_ASSET:-pentris-godot-web-templates-${template_tag}.sha256}"

templates_installed() {
	[ -f "$template_dir/web_nothreads_debug.zip" ] && [ -f "$template_dir/web_nothreads_release.zip" ]
}

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

install_godot_templates() {
	local archive_path="/tmp/$template_asset"
	local checksum_path="/tmp/$template_checksum_asset"
	local extract_root="/tmp/pentris-pages-templates-$template_tag"
	local asset_url="https://github.com/${template_repo}/releases/download/${template_tag}/${template_asset}"
	local checksum_url="https://github.com/${template_repo}/releases/download/${template_tag}/${template_checksum_asset}"

	if templates_installed; then
		return
	fi

	if ! command -v tar >/dev/null 2>&1; then
		echo "missing dependency: tar" >&2
		exit 1
	fi

	if ! command -v sha256sum >/dev/null 2>&1; then
		echo "missing dependency: sha256sum" >&2
		exit 1
	fi

	rm -rf "$extract_root"
	download_file "$asset_url" "$archive_path"
	download_file "$checksum_url" "$checksum_path"

	expected_checksum="$(tr -d ' \n\r' < "$checksum_path")"
	actual_checksum="$(sha256sum "$archive_path" | awk '{print $1}')"
	if [ "$expected_checksum" != "$actual_checksum" ]; then
		echo "custom template checksum mismatch for $template_asset" >&2
		exit 1
	fi

	mkdir -p "$extract_root"
	tar -C "$extract_root" -xzf "$archive_path"

	rm -rf "$template_dir"
	mkdir -p "$template_dir"
	cp -R "$extract_root/." "$template_dir/"

	if ! templates_installed; then
		echo "custom template archive did not install the expected web_nothreads templates" >&2
		exit 1
	fi
}

install_godot_binary() {
	local tool_root="$HOME/.cache/pentris-pages/godot/$godot_version"
	local binary_path="$tool_root/godot4"

	if [ -x "$binary_path" ]; then
		godot_bin="$binary_path"
		return
	fi

	if ! command -v unzip >/dev/null 2>&1; then
		echo "missing dependency: unzip" >&2
		exit 1
	fi

	rm -rf "$tool_root"
	mkdir -p "$tool_root"

	local godot_zip="/tmp/Godot_v${godot_version}_linux.x86_64.zip"

	download_file "https://github.com/godotengine/godot/releases/download/${godot_version}/Godot_v${godot_version}_linux.x86_64.zip" "$godot_zip"
	unzip -q "$godot_zip" -d "$tool_root"
	mv "$tool_root/Godot_v${godot_version}_linux.x86_64" "$binary_path"
	chmod +x "$binary_path"

	godot_bin="$binary_path"
}

if [ -z "$godot_bin" ]; then
	if command -v godot4 >/dev/null 2>&1; then
		godot_bin="$(command -v godot4)"
	else
		install_godot_binary
	fi
fi

install_godot_templates

cd "$repo_root"

"$godot_bin" --headless --path . -s res://tests/test_runner.gd
GODOT_BIN="$godot_bin" ./scripts/build_web.sh release build/web
