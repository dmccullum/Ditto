#!/bin/zsh
# Double-click to build the Mac app (Release, signed with the project's development team so the
# App Group the widgets share works), install it to /Applications, and relaunch it.
# Needs Xcode signed in to that team's Apple account (Xcode → Settings → Accounts).

cd "$(dirname "$0")" || exit 1

xcodebuild -project Ditto.xcodeproj -scheme Ditto -configuration Release -derivedDataPath build/mac \
  -allowProvisioningUpdates -quiet build \
  && osascript -e 'quit app "Ditto"' \
  && rm -rf /Applications/Ditto.app \
  && ditto build/mac/Build/Products/Release/Ditto.app /Applications/Ditto.app \
  && open /Applications/Ditto.app \
  && echo "Ditto installed and launched." \
  || echo "Build failed — see above."
