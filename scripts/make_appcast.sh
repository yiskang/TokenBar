#!/bin/bash
# Emit appcast.xml for a release archive.
#
#   scripts/make_appcast.sh <archive.tar.gz> <version> <build> <tag> <ed-key-file>
#
# Signs the archive with sign_update (Sparkle SPM artifact) and writes
# appcast.xml beside it. Single-item feed: the latest release is the feed.
set -euo pipefail

ARCHIVE="$1"
VERSION="$2"
BUILD="$3"
TAG="$4"
KEY_FILE="$5"

SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
SIGNATURE_LINE=$("$SIGN_UPDATE" -f "$KEY_FILE" "$ARCHIVE")
# sign_update prints: sparkle:edSignature="…" length="…"
ED_SIGNATURE=$(echo "$SIGNATURE_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIGNATURE_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
[ -n "$ED_SIGNATURE" ] && [ -n "$LENGTH" ] || { echo "failed to parse sign_update output" >&2; exit 1; }

ASSET_NAME=$(basename "$ARCHIVE")
URL="https://github.com/Nanako0129/TokenBar-Native/releases/download/$TAG/$ASSET_NAME"
PUB_DATE=$(LC_ALL=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")

cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>TokenBar (native) updates</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <link>https://github.com/Nanako0129/TokenBar-Native/releases/tag/$TAG</link>
      <enclosure
        url="$URL"
        sparkle:edSignature="$ED_SIGNATURE"
        length="$LENGTH"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
echo "appcast.xml written ($VERSION build $BUILD)"
