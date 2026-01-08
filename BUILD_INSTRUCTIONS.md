# Blink Shell - Build Instructions

Automated build script that produces unsigned `.ipa` files for sideloading via signing services.

## Quick Start

### Prerequisites

1. **macOS** with Xcode installed
2. **Xcode Command Line Tools**:
   ```bash
   xcode-select --install
   ```
3. **Xcode platform content**: Install the iOS platform and iOS Simulator runtime
   (Xcode > Settings > Platforms).

### Build Unsigned IPA

```bash
# Build unsigned .ipa (for sideloading)
./build-blink.sh

# Output: dist/Blink-unsigned-v18.4.2.ipa
```

Upload the `.ipa` to your preferred signing service (AltStore, Sideloadly, etc.).

### Build Options

```bash
# Build specific version
./build-blink.sh v18.4.2

# Clean build
./build-blink.sh --clean

# Setup only (download sources, don't build)
./build-blink.sh --setup-only
```

## All Options

```
./build-blink.sh [options] [version]

Options:
  --setup-only     Only setup/clone, don't build
  --build          Build unsigned .ipa (default)
  --clean          Clean build before building
  --archive        Create signed archive (requires Apple Developer account)
  --install        Build and install to device (requires Apple Developer account)
  --keep-build     Keep build-output/ after a successful build
  --keep-source    Keep blink-src/ after a successful build
  --help           Show help message

Examples:
  ./build-blink.sh                    # Build unsigned .ipa
  ./build-blink.sh v18.4.2            # Build specific version
  ./build-blink.sh --clean            # Clean build
  ./build-blink.sh --setup-only       # Only download sources
```

## Output

```
dist/
├── Blink-unsigned-v18.4.2.ipa    # Upload this to signing service
└── Blink-v18.4.2.xcarchive       # Archive builds only

build-output/             # Intermediate build output (removed by default)
├── Products/
└── DerivedData/

blink-src/                # Source checkout (removed by default)
```

## Source Checkout

The script clones Blink into `blink-src/` and applies build-time patches there. The wrapper repo does not modify or ship the Blink source itself.

## Building Future Versions

```bash
./build-blink.sh v19.0.0
```

The script automatically:
- Fetches the specified version
- Downloads required frameworks
- Fixes package dependency issues
- Builds unsigned .ipa

## Troubleshooting

### Package dependency errors
```bash
rm -rf ~/Library/Caches/org.swift.swiftpm
./build-blink.sh --clean
```

### Finding available versions
```bash
git ls-remote --heads https://github.com/blinksh/blink.git | grep -E "v[0-9]+"
```

Or visit: https://github.com/blinksh/blink/branches
