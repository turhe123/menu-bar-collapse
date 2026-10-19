# MenuBarCollapse — AppFactory build rules
- Fully OFFLINE: no web tools, no Swift packages, no brew/npm/pip, no sudo, stay inside this directory.
- Native only: Swift 5.9+, SwiftUI/AppKit + the Apple frameworks in SPEC.md, macOS 14.0+.
- Never change code-signing or deployment settings in `project.yml`.
- Build command (must end with BUILD SUCCEEDED):
  `xcodegen generate && xcodebuild -project MenuBarCollapse.xcodeproj -scheme MenuBarCollapse -configuration Release -derivedDataPath ./build build`
- The .app must land at `build/Build/Products/Release/MenuBarCollapse.app`.
- A visible "Support / Donate ❤️" button must open: https://ko-fi.com/leodavidai
- Full spec: see SPEC.md
