#!/bin/sh
# Builds a copy of cueback to give to someone: dist/cueback.zip, with the program (Apple Silicon and Intel), the
# installer, the Claude skill and the license notices. Their Mac needs no developer tools: unzip, run install.sh.
set -e
cd "$(dirname "$0")/.."
out=dist/cueback
rm -rf "$out" dist/cueback.zip && mkdir -p "$out"

# Each build lands in the same folder, so copy it out before the next one.
swift build -c release --triple arm64-apple-macosx13.0
cp "$(swift build -c release --triple arm64-apple-macosx13.0 --show-bin-path)/cueback" "$out/cueback-arm64"
if swift build -c release --triple x86_64-apple-macosx13.0 >/dev/null 2>&1; then
    cp "$(swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)/cueback" "$out/cueback-x86_64"
    lipo -create "$out/cueback-arm64" "$out/cueback-x86_64" -output "$out/cueback"
    rm "$out/cueback-arm64" "$out/cueback-x86_64"
else
    echo "(the Intel build failed: this copy runs on Apple Silicon only)"
    mv "$out/cueback-arm64" "$out/cueback"
fi
codesign -s - -f "$out/cueback" 2>/dev/null
# Leave the usual build for this Mac in place for install.sh.
swift build -c release >/dev/null

cp scripts/setup.sh "$out/install.sh"
cp skill/SKILL.md THIRD_PARTY_NOTICES.md "$out/"
cat > "$out/README.txt" <<'EOF'
cueback · haptic cues for Claude Code, played on your Mac's trackpad

When Claude asks for permission, finishes, fails or waits for you, your trackpad taps or chimes.
Needs macOS 13 or later and a Force Touch trackpad (a MacBook from 2015 on, or a Magic Trackpad 2).

Install: open Terminal in this folder and run   sh install.sh
         (or tell Claude: "run install.sh in this folder")
You'll feel the "installed" cue. Then tell Claude: "cueback demo çalıştır" (run the cueback demo).

A bell in the menu bar opens its panel: turn the cues on or off, pick a theme (1 Classic, 2 Mochi, 3 Warhorn,
4 Blocky), set the volume and quiet hours, try each cue, play the demo. Its Quit stops cueback until your next
login. You can also tell Claude "tema 2" to switch themes.

Turn it off or on: tell Claude "cueback'i kapat" / "cueback'i aç", or run ~/.local/bin/cueback off / on.
Remove it: tell Claude "cueback'i kaldır".

It adds ~/.local/bin/cueback, a LaunchAgent (app.cueback.daemon), hooks in ~/.claude/settings.json (the old
file is kept next to it as a backup) and a Claude skill in ~/.claude/skills/cueback.
EOF

(cd dist && ditto -c -k --keepParent cueback cueback.zip)
echo "dist/cueback.zip · $(lipo -archs "$out/cueback") · $(du -h dist/cueback.zip | cut -f1)"
