#!/bin/sh
# Runs the offline test and packs the addon as dist/Nerdelandslaget_Riket-<version>.zip,
# with the Nerdelandslaget_Riket folder inside, ready to unpack into Interface\AddOns.
set -e
cd "$(dirname "$0")"
luajit tests/riket_test.lua Nerdelandslaget_Riket
version=$(sed -n 's/^## Version: *//p' Nerdelandslaget_Riket/Nerdelandslaget_Riket.toc | tr -d '\r')
mkdir -p dist
rm -f "dist/Nerdelandslaget_Riket-$version.zip"
zip -qr "dist/Nerdelandslaget_Riket-$version.zip" Nerdelandslaget_Riket
echo "dist/Nerdelandslaget_Riket-$version.zip"
