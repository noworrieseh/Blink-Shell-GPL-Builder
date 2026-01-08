# Blink Shell GPL Builder

This repo is a small wrapper that downloads the Blink Shell GPL source code, removes the paywall, applies a few other build-time fixes, and produces a ready-to-upload IPA.

## What the script does

- Clones Blink into `blink-src/`
- Fixes a couple of Swift package pins
- Makes the vim runtime fetch repeatable
- Applies the GPL sideload paywall patch
- Builds the app and places the output in `dist/`
- Cleans up `build-output/` and `blink-src/` by default


## Requirements

- macOS with Xcode installed
- Xcode Command Line Tools:
  ```bash
  xcode-select --install
  ```
- Xcode platform content: install the iOS platform and iOS Simulator runtime
  (Xcode > Settings > Platforms)

## Quick start

```bash
./build-blink.sh
```

Output:
`dist/Blink-unsigned-v18.4.2.ipa`

Upload the IPA to your signing service (AltStore, Sideloadly, etc).



## Options

```
./build-blink.sh [options] [version]

Options:
  --setup-only     Only setup/clone, don't build
  --build          Build unsigned .ipa (default)
  --simulator      Build and run in iOS Simulator
  --archive        Create signed archive (requires Apple Developer account)
  --install        Build and install to device (requires Apple Developer account)
  --clean          Clean build before building
  --keep-build     Keep build-output/ after a successful build
  --keep-source    Keep blink-src/ after a successful build
  --help           Show help message
```

## Output layout

```
dist/
├── Blink-unsigned-v18.4.2.ipa    # Upload this to signing service
└── Blink-v18.4.2.xcarchive       # Archive builds only

build-output/             # Intermediate build output (removed by default)
├── Products/
└── DerivedData/

blink-src/                # Source checkout (removed by default)
```

## Notes

- Use `--keep-source` if you want to inspect or debug the downloaded Blink source.
- The version defaults to `v18.4.2`. You can override it by passing a version tag:
  ```bash
  ./build-blink.sh v19.0.0
  ```
