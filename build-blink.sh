#!/bin/bash
set -e

# Blink Shell Build Script
# Builds unsigned .ipa for sideloading via signing services
#
# Usage:
#   ./build-blink.sh [options] [version]
#
# Options:
#   --setup-only     Only setup/clone, don't build
#   --build          Build unsigned .ipa (default)
#   --clean          Clean build before building
#   --simulator      Build and run in iOS Simulator
#   --archive        Create signed archive (requires dev account)
#   --install        Build and install to connected device (requires dev account)
#   --keep-build     Keep build-output/ after a successful build
#   --keep-source    Keep blink-src/ after a successful build
#   --help           Show this help message
#
# Examples:
#   ./build-blink.sh                    # Build unsigned .ipa
#   ./build-blink.sh v18.4.2            # Build specific version
#   ./build-blink.sh --setup-only       # Only setup, don't build
#   ./build-blink.sh --clean            # Clean build

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VERSION="v18.4.2"
SOURCE_DIR="${SCRIPT_DIR}/blink-src"
BUILD_DIR="${SCRIPT_DIR}/build-output"
OUTPUT_DIR="${SCRIPT_DIR}/dist"
OUTPUT_ARCHIVE_PATH=""
OUTPUT_IPA_PATH=""
SCHEME="Blink"
PROJECT="${SOURCE_DIR}/Blink.xcodeproj"

# Options
SETUP_ONLY=false
DO_BUILD=true
DO_CLEAN=false
DO_ARCHIVE=false
DO_INSTALL=false
DO_SIMULATOR=false
KEEP_BUILD=false
KEEP_SOURCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --setup-only)
            SETUP_ONLY=true
            DO_BUILD=false
            shift
            ;;
        --build)
            DO_BUILD=true
            shift
            ;;
        --clean)
            DO_CLEAN=true
            shift
            ;;
        --archive)
            DO_ARCHIVE=true
            shift
            ;;
        --install)
            DO_INSTALL=true
            shift
            ;;
        --simulator)
            DO_SIMULATOR=true
            DO_BUILD=false
            shift
            ;;
        --keep-build)
            KEEP_BUILD=true
            shift
            ;;
        --keep-source)
            KEEP_SOURCE=true
            shift
            ;;
        --help)
            head -25 "$0" | tail -22
            exit 0
            ;;
        v*)
            VERSION="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "=================================="
echo "Blink Shell Build Script"
echo "=================================="
echo "Version: $VERSION"
echo "Source directory: $SOURCE_DIR"
echo ""

# Function to fix package dependencies
fix_package_dependencies() {
    echo "Fixing package dependencies..."

    # Fix swiftui-cached-async-image (main branch has broken Package.swift)
    if grep -q 'XCRemoteSwiftPackageReference "swiftui-cached-async-image"' "${PROJECT}/project.pbxproj" 2>/dev/null; then
        sed -i '' '/XCRemoteSwiftPackageReference "swiftui-cached-async-image"/,/};/{
            s/branch = main;/kind = upToNextMajorVersion;/
            s/kind = branch;/minimumVersion = 1.9.0;/
            s/minimumVersion = [0-9.][0-9.]*;/minimumVersion = 1.9.0;/
        }' "${PROJECT}/project.pbxproj"
        echo "  Fixed swiftui-cached-async-image package"
    fi

    # Fix SwiftCBOR (master branch tracking causes issues)
    if grep -q 'XCRemoteSwiftPackageReference "SwiftCBOR"' "${PROJECT}/project.pbxproj" 2>/dev/null; then
        sed -i '' '/XCRemoteSwiftPackageReference "SwiftCBOR"/,/};/{
            s/branch = master;/kind = upToNextMajorVersion;/
            s/kind = branch;/minimumVersion = 0.4.0;/
            s/minimumVersion = [0-9.][0-9.]*;/minimumVersion = 0.4.0;/
        }' "${PROJECT}/project.pbxproj"
        echo "  Fixed SwiftCBOR package"
    fi

    # Clear SPM cache to avoid stale manifests
    rm -rf ~/Library/Caches/org.swift.swiftpm/manifests 2>/dev/null || true
    rm -rf "${SOURCE_DIR}/Blink.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" 2>/dev/null || true
}


# Function to remove paywall (GPL sideload build)
patch_remove_paywall() {
    echo "Patching: Removing paywall for GPL sideload build..."

    local ENTITLEMENTS_FILE="${SOURCE_DIR}/Blink/Subscriptions/EntitlementsManager.swift"

    if [ -f "$ENTITLEMENTS_FILE" ]; then
        if ! grep -q 'private func _currentPlanName()' "$ENTITLEMENTS_FILE"; then
            perl -0pi -e 's@public func currentPlanName\\(\\) -> String \\{@public func currentPlanName() -> String {\\n    return \"GPL Sideload Build\"\\n  }\\n\\n  private func _currentPlanName() -> String {@s' "$ENTITLEMENTS_FILE"
        fi

        if ! grep -q 'private func _customerTier()' "$ENTITLEMENTS_FILE"; then
            perl -0pi -e 's@public func customerTier\\(\\) -> CustomerTier \\{@public func customerTier() -> CustomerTier {\\n    return CustomerTier.Classic\\n  }\\n\\n  private func _customerTier() -> CustomerTier {@s' "$ENTITLEMENTS_FILE"
        fi

        if ! grep -q 'private func _hasActiveSubscriptions()' "$ENTITLEMENTS_FILE"; then
            perl -0pi -e 's@public func hasActiveSubscriptions\\(\\) -> Bool \\{@public func hasActiveSubscriptions() -> Bool {\\n    return true\\n  }\\n\\n  private func _hasActiveSubscriptions() -> Bool {@s' "$ENTITLEMENTS_FILE"
        fi

        echo "  Paywall removed (idempotent patch)"
    else
        echo "  Warning: EntitlementsManager.swift not found"
    fi
}

# Function to fix get_resources.sh for repeated runs
fix_get_resources_script() {
    local SCRIPT_FILE="${SOURCE_DIR}/get_resources.sh"

    if [ -f "$SCRIPT_FILE" ] && grep -q 'mv runtime/\*' "$SCRIPT_FILE" 2>/dev/null; then
        echo "Fixing get_resources.sh for repeated runs..."
        sed -i '' 's/unzip runtime.zip && mv runtime\/\* .\/ && rm runtime.zip/unzip -o runtime.zip \&\& cp -rf runtime\/* .\/ \&\& rm -rf runtime runtime.zip/' "$SCRIPT_FILE"
    fi
}

# Function to create sideload-friendly entitlements
create_sideload_entitlements() {
    echo "Creating sideload-friendly entitlements..."

    local ENTITLEMENTS_FILE="${SOURCE_DIR}/Blink/Blink-sideload.entitlements"

    cat > "$ENTITLEMENTS_FILE" << 'ENTITLEMENTS_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.default-data-protection</key>
	<string>NSFileProtectionComplete</string>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.device.bluetooth</key>
	<true/>
	<key>com.apple.security.device.camera</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.security.personal-information.location</key>
	<true/>
</dict>
</plist>
ENTITLEMENTS_EOF

    echo "  Created Blink-sideload.entitlements"
}

# Function to setup/clone repository
setup_repository() {
    if [ -d "$SOURCE_DIR" ]; then
        echo "Source directory already exists."
        read -p "Do you want to clean and re-clone? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Removing existing source directory..."
            rm -rf "$SOURCE_DIR"
        else
            echo "Using existing source directory..."
            cd "$SOURCE_DIR"

            echo "Fetching latest changes..."
            git fetch --all --tags

            echo "Checking out $VERSION..."
            git checkout "$VERSION"
            git submodule update --init --recursive

            echo "Running framework setup..."
            ./get_frameworks.sh

            fix_get_resources_script
            echo "Running resource setup..."
            ./get_resources.sh

            echo "Cleaning Xcode workspace..."
            rm -rf Blink.xcodeproj/project.xcworkspace/xcshareddata/

            fix_package_dependencies
            patch_remove_paywall
            create_sideload_entitlements
            return 0
        fi
    fi

    echo "Cloning Blink repository (version: $VERSION)..."
    git clone --recursive --branch "$VERSION" https://github.com/blinksh/blink.git "$SOURCE_DIR"

    cd "$SOURCE_DIR"

    echo "Running framework setup..."
    ./get_frameworks.sh

    fix_get_resources_script
    echo "Running resource setup..."
    ./get_resources.sh

    if [ ! -f "developer_setup.xcconfig" ]; then
        echo "Creating developer_setup.xcconfig from template..."
        cp template_setup.xcconfig developer_setup.xcconfig
    fi

    echo "Cleaning Xcode workspace..."
    rm -rf Blink.xcodeproj/project.xcworkspace/xcshareddata/

    fix_package_dependencies
    patch_remove_paywall
    create_sideload_entitlements
}

# Function to resolve packages
resolve_packages() {
    echo ""
    echo "Resolving package dependencies..."
    xcodebuild -resolvePackageDependencies \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        2>&1 | grep -E "(Resolved|Fetching|Checking out|error:|warning:)" || true
}

# Function to run xcodebuild with optional xcpretty
run_xcodebuild() {
    if command -v xcpretty &> /dev/null; then
        "$@" 2>&1 | xcpretty
    else
        "$@"
    fi
}

# Function to build
build_app() {
    local EXTRA_FLAGS=""

    if [ "$DO_CLEAN" = true ]; then
        EXTRA_FLAGS="clean build"
    else
        EXTRA_FLAGS="build"
    fi

    echo ""
    echo "Building Blink Shell..."
    echo ""

    mkdir -p "$BUILD_DIR"

    if [ "$DO_SIMULATOR" = true ]; then
        # Build and run in iOS Simulator
        echo "Building for iOS Simulator..."

        # Boot simulator if needed
        SIMULATOR_ID=$(xcrun simctl list devices available | grep -E "iPhone (15|16)" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')

        if [ -z "$SIMULATOR_ID" ]; then
            echo "No suitable iPhone simulator found. Creating one..."
            SIMULATOR_ID=$(xcrun simctl create "iPhone 15" "com.apple.CoreSimulator.SimDeviceType.iPhone-15")
        fi

        echo "Using simulator: $SIMULATOR_ID"
        xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true

        run_xcodebuild xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination "id=$SIMULATOR_ID" \
            -derivedDataPath "${BUILD_DIR}/DerivedData" \
            -skipPackagePluginValidation \
            -skipMacroValidation \
            ENABLE_DEBUG_DYLIB=NO \
            $EXTRA_FLAGS

        # Open Simulator and launch app
        open -a Simulator
        sleep 2

        # Find and install the app
        APP_PATH=$(find "${BUILD_DIR}/DerivedData" -name "Blink.app" -path "*Debug-iphonesimulator*" | head -1)
        if [ -n "$APP_PATH" ]; then
            xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
            xcrun simctl launch "$SIMULATOR_ID" sh.blink.blinkshell
            echo "Blink launched in simulator"
        else
            echo "Error: Could not find simulator build"
            exit 1
        fi

    elif [ "$DO_INSTALL" = true ]; then
        # Build and install to connected device
        echo "Building and installing to connected device..."

        # Get connected device ID
        DEVICE_ID=$(xcrun xctrace list devices 2>&1 | grep -E "iPhone|iPad" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')

        if [ -z "$DEVICE_ID" ]; then
            echo "Error: No iOS device connected. Please connect a device and try again."
            exit 1
        fi

        echo "Installing to device: $DEVICE_ID"

        run_xcodebuild xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination "id=$DEVICE_ID" \
            -derivedDataPath "${BUILD_DIR}/DerivedData" \
            -skipPackagePluginValidation \
            -skipMacroValidation \
            $EXTRA_FLAGS
    elif [ "$DO_ARCHIVE" = true ]; then
        # Build archive
        ARCHIVE_PATH="${BUILD_DIR}/Blink.xcarchive"
        echo "Creating archive at: $ARCHIVE_PATH"

        run_xcodebuild xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination 'generic/platform=iOS' \
            -derivedDataPath "${BUILD_DIR}/DerivedData" \
            -archivePath "$ARCHIVE_PATH" \
            -skipPackagePluginValidation \
            -skipMacroValidation \
            archive

        mkdir -p "$OUTPUT_DIR"
        OUTPUT_ARCHIVE_PATH="${OUTPUT_DIR}/Blink-${VERSION}.xcarchive"
        if [ "$KEEP_BUILD" = true ]; then
            cp -R "$ARCHIVE_PATH" "$OUTPUT_ARCHIVE_PATH"
        else
            mv "$ARCHIVE_PATH" "$OUTPUT_ARCHIVE_PATH"
        fi

        echo ""
        echo "Archive created: $OUTPUT_ARCHIVE_PATH"
    else
        # Generic iOS build (unsigned .ipa for sideloading)
        # Use sideload-friendly entitlements (no iCloud, Push, etc.)
        run_xcodebuild xcodebuild \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -destination 'generic/platform=iOS' \
            -derivedDataPath "${BUILD_DIR}/DerivedData" \
            CONFIGURATION_BUILD_DIR="${BUILD_DIR}/Products" \
            -skipPackagePluginValidation \
            -skipMacroValidation \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGN_ENTITLEMENTS="${SOURCE_DIR}/Blink/Blink-sideload.entitlements" \
            $EXTRA_FLAGS

        # Package as unsigned .ipa
        echo ""
        echo "Packaging unsigned .ipa for sideloading..."
        APP_PATH="${BUILD_DIR}/Products/Blink.app"
        IPA_PATH="${BUILD_DIR}/Blink-unsigned.ipa"
        OUTPUT_IPA_PATH="${OUTPUT_DIR}/Blink-unsigned-${VERSION}.ipa"

        if [ -d "$APP_PATH" ]; then
            # Create Payload directory structure
            PAYLOAD_DIR="${BUILD_DIR}/Payload"
            rm -rf "$PAYLOAD_DIR"
            mkdir -p "$PAYLOAD_DIR"
            cp -r "$APP_PATH" "$PAYLOAD_DIR/"

            # Remove app extensions that require entitlements incompatible with sideloading
            echo "Removing incompatible app extensions..."
            rm -rf "$PAYLOAD_DIR/Blink.app/PlugIns"

            # Create .ipa (which is just a zip file)
            cd "$BUILD_DIR"
            rm -f "Blink-unsigned.ipa"
            zip -r -q "Blink-unsigned.ipa" Payload
            rm -rf "$PAYLOAD_DIR"
            cd "$SCRIPT_DIR"

            mkdir -p "$OUTPUT_DIR"
            if [ "$KEEP_BUILD" = true ]; then
                cp -f "$IPA_PATH" "$OUTPUT_IPA_PATH"
            else
                mv "$IPA_PATH" "$OUTPUT_IPA_PATH"
            fi

            echo "Created: $OUTPUT_IPA_PATH"
        else
            echo "Error: Build failed - Blink.app not found"
            exit 1
        fi
    fi
}

# Main execution
setup_repository

if [ "$SETUP_ONLY" = true ]; then
    echo ""
    echo "=================================="
    echo "Setup complete!"
    echo "=================================="
    echo ""
    echo "Next steps:"
    echo "1. Edit developer_setup.xcconfig and update TEAM_ID:"
    echo "   nano $SOURCE_DIR/developer_setup.xcconfig"
    echo ""
    echo "2. Build from command line:"
    echo "   $0 --build"
    echo ""
    echo "3. Or open in Xcode:"
    echo "   open $PROJECT"
    exit 0
fi

resolve_packages

if [ "$DO_BUILD" = true ] || [ "$DO_INSTALL" = true ] || [ "$DO_ARCHIVE" = true ] || [ "$DO_SIMULATOR" = true ]; then
    build_app
    if [ "$KEEP_BUILD" = false ]; then
        echo ""
        echo "Cleaning build output..."
        rm -rf "$BUILD_DIR"
    fi
    if [ "$KEEP_SOURCE" = false ]; then
        echo "Cleaning source checkout..."
        rm -rf "$SOURCE_DIR"
    fi
fi

echo ""
echo "=================================="
echo "Build complete!"
echo "=================================="
echo ""

if [ "$DO_SIMULATOR" = true ]; then
    echo "Blink is running in the iOS Simulator."
elif [ "$DO_INSTALL" = true ]; then
    echo "App has been installed to your device."
elif [ "$DO_ARCHIVE" = true ]; then
    echo "Archive location: ${OUTPUT_ARCHIVE_PATH}"
else
    echo "Unsigned IPA: ${OUTPUT_IPA_PATH}"
    echo ""
    echo "Upload this .ipa to your signing service for sideloading."
fi
echo ""
