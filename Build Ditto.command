#!/bin/zsh
# Double-click to build the Mac app (Release, ad-hoc signed, no Apple account needed),
# install it to /Applications, and relaunch it.

cd "$(dirname "$0")" || exit 1

xcodebuild -project Ditto.xcodeproj -scheme Ditto -configuration Release -derivedDataPath build/mac \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -quiet build \
  && osascript -e 'quit app "Ditto"' \
  && rm -rf /Applications/Ditto.app \
  && ditto build/mac/Build/Products/Release/Ditto.app /Applications/Ditto.app \
  && open /Applications/Ditto.app \
  && echo "Ditto installed and launched." \
  || echo "Build failed — see above."
