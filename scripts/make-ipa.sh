#!/usr/bin/env bash
# Builds an UNSIGNED Release .ipa at build/PhoneMirror.ipa (app + broadcast extension).
# AltStore/SideStore re-sign it (including the extension) with your Apple ID on
# install, so no signing identity or team is needed here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/ipa"
OUT="$ROOT/build/PhoneMirror.ipa"

xcodebuild -project "$ROOT/PhoneMirror.xcodeproj" -scheme PhoneMirrorSend \
  -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -quiet build

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/Payload"
cp -R "$DD/Build/Products/Release-iphoneos/PhoneMirrorSend.app" "$WORK/Payload/"
rm -f "$OUT"
(cd "$WORK" && zip -qry "$OUT" Payload)

echo "$OUT"
