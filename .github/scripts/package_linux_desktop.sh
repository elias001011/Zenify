#!/usr/bin/env bash
# Builds Zenify-linux-x64.deb and Zenify-linux-x64.tar.gz from the release bundle.
set -euo pipefail

APP_NAME="zenify"
APP_ID="io.github.elias001011.zenify"
BUNDLE_DIR="build/linux/x64/release/bundle"
DIST_DIR="build/desktop-artifacts"
VERSION="$(sed -n 's/^version: \([^ +]*\).*/\1/p' pubspec.yaml)"
PACKAGE_VERSION="${VERSION}-${DEB_REVISION:-1}"
PACKAGE_ROOT="build/linux-package/${APP_NAME}_${PACKAGE_VERSION}_amd64"
APP_DIR="${PACKAGE_ROOT}/usr/lib/${APP_NAME}"
ICON="${BUNDLE_DIR}/data/flutter_assets/assets/icons/ic_launcher.png"

if [[ ! -x "${BUNDLE_DIR}/${APP_NAME}" ]]; then
  echo "Linux release bundle not found at ${BUNDLE_DIR}" >&2
  exit 1
fi

rm -rf "${DIST_DIR}" "${PACKAGE_ROOT}"
mkdir -p "${DIST_DIR}" "${APP_DIR}" "${PACKAGE_ROOT}/DEBIAN" \
  "${PACKAGE_ROOT}/usr/bin" \
  "${PACKAGE_ROOT}/usr/share/applications" \
  "${PACKAGE_ROOT}/usr/share/icons/hicolor/96x96/apps"

cp -R "${BUNDLE_DIR}/." "${APP_DIR}/"
# The package installs its own menu entry, so the tarball helper is not needed.
rm -f "${APP_DIR}/install-linux-desktop.sh"
ln -s "/usr/lib/${APP_NAME}/${APP_NAME}" "${PACKAGE_ROOT}/usr/bin/${APP_NAME}"
install -m 0644 "${ICON}" \
  "${PACKAGE_ROOT}/usr/share/icons/hicolor/96x96/apps/${APP_NAME}.png"

# Same entry as linux/install-linux-desktop.sh writes for the tarball.
cat > "${PACKAGE_ROOT}/usr/share/applications/${APP_ID}.desktop" <<DESKTOP
[Desktop Entry]
Name=Zenify
Comment=Music Streaming app
Exec=${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Type=Application
Categories=AudioVideo;Audio;Player;
StartupWMClass=${APP_ID}
DESKTOP

cat > "${PACKAGE_ROOT}/DEBIAN/control" <<CONTROL
Package: ${APP_NAME}
Version: ${PACKAGE_VERSION}
Section: sound
Priority: optional
Architecture: amd64
Maintainer: Zenify Contributors <noreply@github.com>
Installed-Size: $(du -sk "${PACKAGE_ROOT}/usr" | cut -f1)
Depends: libgtk-3-0, libstdc++6, libmpv2 | libmpv1
Description: Music streaming app made in Flutter
CONTROL

chmod -R go-w "${PACKAGE_ROOT}"
dpkg-deb --root-owner-group --build "${PACKAGE_ROOT}" "${DIST_DIR}/Zenify-linux-x64.deb"
tar -C "${BUNDLE_DIR}" -czf "${DIST_DIR}/Zenify-linux-x64.tar.gz" .
