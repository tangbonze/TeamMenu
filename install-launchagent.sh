#!/bin/bash
# Register TeamMenu as a LaunchAgent so it auto-starts at login and stays resident.
set -euo pipefail
cd "$(dirname "$0")"

APP_PATH="$(cd .. && pwd)/outputs/TeamMenu.app"
LABEL="com.teammenu.TeamMenu"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -x "$APP_PATH/Contents/MacOS/TeamMenu" ]; then
  echo "App not built yet. Run ./build.sh first." >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$APP_PATH/Contents/MacOS/TeamMenu</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null || true
echo "Installed & started LaunchAgent: $LABEL"
echo "Stop with:  launchctl bootout gui/$(id -u) $PLIST"
echo "Uninstall:  launchctl bootout gui/$(id -u) $PLIST; rm $PLIST"
