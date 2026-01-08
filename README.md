# Blink Shell GPL Builder

This repo is a small script that downloads the [Blink Shell](https://github.com/blinksh/blink) GPL source code, removes the paywall, applies a few other build-time fixes, and produces a ready-to-upload IPA.

## What the script does

- Clones the Blink Shell repo into `blink-src/`
- Applies the GPL sideload paywall patch
- Fixes a couple of Swift package pins
- Makes the vim runtime fetch repeatable
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
- Git and Python 3

The script runs preflight checks and exits early with clear errors if anything
is missing.

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
  --non-interactive Skip prompts and reuse existing blink-src/
  --skip-migrator  Skip app migrations (debug)
  --minimal-entitlements Use stripped entitlements (debug)
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
- The version defaults to `v18.4.2`. You can override it by passing a Blink
  branch name from the Blink repo (most releases are published as branches):
  ```bash
  ./build-blink.sh v19.0.0
  ```
- The build uses Blink’s default entitlements and migrations by default.
- If a sideloaded build crashes at launch, try `--skip-migrator`.
- If your signing service rejects the IPA due to entitlements, try
  `--minimal-entitlements`.
- The script skips Blink’s migration step in sideload builds to avoid assertion
  failures when App Group containers aren’t available.

## Troubleshooting

Package dependency errors:
```bash
rm -rf ~/Library/Caches/org.swift.swiftpm
./build-blink.sh --clean
```

Finding available versions (Blink publishes release branches in the repo):
```bash
git ls-remote --heads https://github.com/blinksh/blink.git | grep -E "refs/heads/v[0-9]+"
```

## License

MIT. See `LICENSE`.
