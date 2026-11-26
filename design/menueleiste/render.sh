#!/usr/bin/env bash
# Rendert das Menüleisten-Symbol (18 pt, 1x/2x/3x) in das Template-Imageset MenuBarGnotchi.
# Quelle: gnotchi.svg hier (Kopie aus dem Vault, 07 Anhänge/Brand-Characters/familie/menueleiste).
set -euo pipefail
cd "$(dirname "$0")"
A=../../Gnotchi/Resources/Assets.xcassets/MenuBarGnotchi.imageset
for k in 1 2 3; do
  suf=""; [ "$k" -gt 1 ] && suf="@${k}x"
  w=$((18 * k))
  magick -density 1152 -background none gnotchi.svg -resize "${w}x${w}" "PNG32:$A/gnotchi$suf.png"
done
echo "Menüleisten-Symbol gerendert."
