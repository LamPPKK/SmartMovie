# Apple artwork sources

## Purpose

This directory keeps the editable masters used by the Apple asset catalogs. Generated catalog PNGs live under `SmartMovie/Assets.xcassets`; do not edit those derivatives independently.

## Current masters

- `AppIconMaster-Opaque.png`: square, opaque SmartMovie icon master for iOS, iPadOS, macOS, Catalyst, and watchOS derivatives.
- `SmartMovieMark.svg`: transparent vector source for the white geometric SmartMovie mark used in layered artwork.
- `TVBackgroundMaster.png`: opaque blue/wave background source for tvOS parallax icon layers.
- `TopShelfMaster.png`: opaque wide source for standard and wide Top Shelf images.
- `LegacyAppIcon/`: pre-3.0 PNG set retained only as recoverable design history; it is not compiled into any target.

The image-generation briefs were:

1. App icon: a polished, cinematic SmartMovie catalog icon with a deep electric-blue field, a crisp white geometric movie mark, restrained pale wave accents, no text, no transparency, and no pre-applied rounded-corner mask.
2. Top Shelf: a wide cinematic blue banner with the same white mark centered, flowing pale film-like waves kept away from the safe center, no text, and an opaque background.
3. Layer background: the Top Shelf blue/wave environment without the center mark, leaving a calm central safe area for a separate foreground layer.

The final generated masters are committed at the paths above. `SmartMovieMark.svg` was recreated as clean vector geometry because the generated transparent logo extraction had noisy edges and was not suitable for production.

## Compiled asset layout

- `AppIcon.appiconset` contains opaque iOS/iPadOS and Mac/Catalyst PNGs.
- `WatchAppIcon.appiconset` is intentionally separate. The Watch target selects it through `ASSETCATALOG_COMPILER_APPICON_NAME`, preventing Watch-only marketing artwork from appearing as an unassigned Mac child.
- `AppIcon.brandassets` contains two-layer small/large tvOS icons and standard/wide Top Shelf images.
- `VisionAppIcon.solidimagestack` contains an opaque 1024×1024 back layer and a transparent 1024×1024 front mark. The visionOS target selects this stack explicitly.
- `LaunchBackground.colorset` supplies the named color used by the `UILaunchScreen` dictionary.

tvOS background layers and all Top Shelf images must remain opaque. Foreground icon layers must retain transparency. Store icons must not contain alpha, rounded corners, or a baked system mask.

Apple references: [Configuring your app icon using an asset catalog](https://developer.apple.com/documentation/xcode/configuring-your-app-icon), [App icons HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons), [Top Shelf HIG](https://developer.apple.com/design/human-interface-guidelines/top-shelf), [Brand Assets catalog format](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/BrandAssetsType.html), and [`UILaunchScreen`](https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen).

## Verification

Regenerate `SmartMovie.xcodeproj` after any catalog or target-setting change:

```sh
xcodegen generate --spec SmartMovie/project.yml
```

Then run the unsigned platform builds from the repository root as documented in `docs/TESTING.md`. A successful asset-only verification has both of these properties:

- `xcodebuild -quiet` produces no Asset Catalog Compiler warning for a missing icon, Top Shelf asset, or unassigned child.
- The built iOS app's `Info.plist` contains `UILaunchScreen` with `UIColorName` equal to `LaunchBackground`.

visionOS icon compilation must be repeated on an Apple-silicon runner with a visionOS runtime. An installed SDK alone is insufficient for `actool` on an Intel host. The Xcode workflow captures every platform build log and fails if it finds an Asset Catalog Compiler document warning or a missing icon, Top Shelf, or launch-screen warning.

## Rollback and updates

If new artwork fails compilation, restore the last known-good compiled catalog from Git while keeping the proposed master outside `Assets.xcassets` for review. Do not solve a catalog warning by leaving an unreferenced PNG inside an app-icon set. Any replacement must preserve the SmartMovie mark, platform-safe center, opacity rules, and all declared pixel dimensions.
