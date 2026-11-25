#!/bin/sh
# Installs cueback from a folder that holds the built program and SKILL.md (in a shared copy, this script's own
# folder): the program as ~/.local/bin/cueback, its background service (a LaunchAgent that starts at login and
# comes back if it stops), Claude Code's hooks and the Claude skill. Plays the "installed" cue the first time.
set -e
[ "$(uname -s)" = Darwin ] || { echo "cueback runs on macOS only." >&2; exit 1; }
src="$(cd "${1:-$(dirname "$0")}" && pwd)"
label=app.cueback.daemon
domain="gui/$(id -u)"
bin="$HOME/.local/bin/cueback"
plist="$HOME/Library/LaunchAgents/$label.plist"
first=1
[ -e "$plist" ] && first=0

mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs" "$HOME/.claude/skills/cueback"
install -m 755 "$src/cueback" "$bin"
xattr -d com.apple.quarantine "$bin" 2>/dev/null || true   # a copy that came by AirDrop or a download
install -m 644 "$src/SKILL.md" "$HOME/.claude/skills/cueback/SKILL.md"

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$bin</string><string>daemon</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/cueback.log</string>
</dict>
</plist>
EOF

# Start (or restart) the daemon on this build.
launchctl bootout "$domain/$label" 2>/dev/null || true
i=0
while launchctl print "$domain/$label" >/dev/null 2>&1 && [ "$i" -lt 25 ]; do sleep 0.2; i=$((i + 1)); done
launchctl bootstrap "$domain" "$plist"

"$bin" install-hooks

i=0
until "$bin" status | grep -q 'daemon running' || [ "$i" -ge 25 ]; do sleep 0.2; i=$((i + 1)); done
if [ "$first" = 1 ]; then "$bin" play installed || true; fi
echo "cueback is installed. Try it: ask Claude to run the cueback demo, or run ~/.local/bin/cueback demo"
echo "It drives the trackpad's motor through a private macOS framework and comes with no warranty: you use it at your own risk."
