#!/bin/sh
set -eu

bundle_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
binary="$bundle_dir/zenify"
icon="$bundle_dir/data/flutter_assets/assets/icons/ic_launcher.png"

if [ ! -x "$binary" ]; then
  printf 'Zenify executable not found: %s\n' "$binary" >&2
  exit 1
fi

if [ ! -f "$icon" ]; then
  printf 'Zenify icon not found: %s\n' "$icon" >&2
  exit 1
fi

data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
applications_dir="$data_home/applications"
icons_dir="$data_home/icons/hicolor/96x96/apps"
app_id=io.github.elias001011.zenify
desktop_file="$applications_dir/$app_id.desktop"
temporary_desktop_file="$desktop_file.tmp.$$"

mkdir -p "$applications_dir" "$icons_dir"
# Named after the app id, as desktops expect; older installs used "zenify".
install -m 644 "$icon" "$icons_dir/$app_id.png"
rm -f "$icons_dir/zenify.png"

escaped_binary=$(printf '%s' "$binary" | sed 's/[\\"]/\\&/g; s/%/%%/g')
trap 'rm -f "$temporary_desktop_file"' 0 HUP INT TERM
{
  printf '[Desktop Entry]\n'
  printf 'Name=Zenify\n'
  printf 'Comment=Music Streaming app\n'
  printf 'Exec="%s"\n' "$escaped_binary"
  printf 'Icon=%s\n' "$app_id"
  printf 'Terminal=false\n'
  printf 'Type=Application\n'
  printf 'Categories=AudioVideo;Audio;Player;\n'
  printf 'StartupWMClass=%s\n' "$app_id"
} > "$temporary_desktop_file"
chmod 644 "$temporary_desktop_file"
mv -f "$temporary_desktop_file" "$desktop_file"

printf 'Installed Zenify desktop entry: %s\n' "$desktop_file"
