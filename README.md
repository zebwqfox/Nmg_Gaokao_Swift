# 内蒙古高考助手

iOS 26-only SwiftUI MVP for the official Inner Mongolia exam sites.

## Build

The app is defined with XcodeGen:

```sh
cd apps/ios
xcodegen generate
xcodebuild \
  -project NeimengGaokao.xcodeproj \
  -scheme NeimengGaokao \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The GitHub Actions workflow at `.github/workflows/ios26ui-unsigned-ipa-build.yml` runs the same flow on `macos-26`, verifies Xcode 26, generates the project, builds without code signing, and uploads an unsigned IPA.

## Scope

- iOS target: 26.0 only.
- UI: native SwiftUI Liquid Glass surfaces and glass button styles.
- Official student workflows: opened in controlled `WKWebView`.
- Official session bridge: native login stores official token and `baseUserInfo`, then injects encrypted `STUTOKEN` / `BASEUSERINFO` into `WKWebView`.
- Services tab: prefers live official `stusercenter/serlist` entries, with local fallback shortcuts.
- Official news and policy content: fetched directly from `www.nm.zsks.cn`, cached locally with SwiftData.
- Backend: optional future extension; the MVP does not require it for login, browsing, service launch, or policy feed.

See `docs/ARCHITECTURE.md` for architecture, file structure, local data schema, official endpoints, and UI structure.
