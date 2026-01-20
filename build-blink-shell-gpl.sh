#!/bin/bash

# HELP_START
# Blink Shell Build Script
# Builds unsigned .ipa for sideloading via signing services
#
# Usage:
#   ./build-blink-shell-gpl.sh [options]
#
# Options:
#   --version <version>      Version to checkout.  Default: v18.4.2
#   --setup-only             Only setup/clone, don't build
#   --update                 Update existing source
#   --overwrite              Overwrite existing source
#   --clean                  Clean build before building
#   --clean-all              Remove source and build directories
#   --unsigned-ipa           Build unsigned .ipa (default)
#   --signed-ipa             Build signed .ipa
#   --archive                Build signed archive (requires dev account)
#   --simulator [<name|id>]  Build and run in iOS Simulator
#   --install [<name|id>]    Build and install to connected device (requires dev account)
#   --keep-build             Keep build-output/ after a successful build
#   --keep-source            Keep blink-src/ after a successful build
#   --simulators             List compatible simulators (requires blink src)
#   --devices                List compatible devices (requires blink src)
#   --help                   Show this help message
#
# Examples:
#   ./build-blink-shell-gpl.sh                    # Build unsigned .ipa
#   ./build-blink-shell-gpl.sh v18.4.2            # Build specific version
#   ./build-blink-shell-gpl.sh --setup-only       # Only setup, don't build
#   ./build-blink-shell-gpl.sh --clean            # Clean build
# HELP_END

# Constants
PAT_DEVID="^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$"
PAT_UUID="^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{6}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{16}$"
CONF_RELEASE="Release"
CONF_DEBUG="Debug"
PLIST="/usr/libexec/PlistBuddy"
PLISTJ="plutil -convert json -o -"

# Locations
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SOURCE_DIR="${SCRIPT_DIR}/blink-src"
BUILD_DIR="${SCRIPT_DIR}/build-output"
BUILD_LOG="${BUILD_DIR}/build.log"
OUTPUT_DIR="${SCRIPT_DIR}/dist"
PROJECT="${SOURCE_DIR}/Blink.xcodeproj"
PROJECT_FILE="${PROJECT}/project.pbxproj"
DEVSETUP="${SOURCE_DIR}/developer_setup.xcconfig"
XCLIST="${BUILD_DIR}/xclist"
XCSHARED="${PROJECT}/project.xcworkspace/xcshareddata"

# Global Variables
BLINK_REPO="https://github.com/blinksh/blink.git"
VERSION="v18.4.2"
SCHEME="Blink"
DEVICE=""
TEMPLATE=""
MIN_PLATFORM=""
TEAM_ID=""
BUNDLE_ID=""

# Option Settings
SETUP_ONLY=false
DO_UNSIGNED_IPA=true
DO_SIGNED_IPA=false
DO_ARCHIVE=false
DO_INSTALL=false
DO_SIMULATOR=false
LIST_DEVICES=false
LIST_SIMS=false

BUILD_CLEAN=false
BUILD_KEEP=false

SOURCE_UPDATE=false
SOURCE_OVERWRITE=false
SOURCE_KEEP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --setup-only)
            SETUP_ONLY=true
            ;;
        --update)
            SOURCE_UPDATE=true
            ;;
        --overwrite)
            SOURCE_OVERWRITE=true
            ;;
        --clean)
            DO_CLEAN=true
            ;;
        --clean-all)
            rm -fr "${SOURCE_DIR}" "${BUILD_DIR}" 2>/dev/null
            exit 0
            ;;
        --unsigned-ipa)
            DO_UNSIGNED_IPA=true
            ;;
        --signed-ipa)
            DO_SIGNED_IPA=true
            DO_UNSIGNED_IPA=false
            ;;
        --archive)
            DO_ARCHIVE=true
            DO_UNSIGNED_IPA=false
            ;;
        --install)
            DO_INSTALL=true
            DO_UNSIGNED_IPA=false
            shift
            # Check for optional device name/id
            if [[ $# -gt 0 && "$1" != "--"* ]]; then
                DEVICE="$1"
            else
                continue
            fi
            ;;
        --simulator)
            DO_SIMULATOR=true
            DO_UNSIGNED_IPA=false
            shift
            # Check for optional simulator name/id
            if [[ $# -gt 0 && "$1" != "--"* ]]; then
                DEVICE="$1"
            else
                continue
            fi
            ;;
        --dev)
            shift
            if [[ $# -gt 0 && "$1" != "--"* && -e "$1" ]]; then
                FILE="$1"
                if [[ ! -f $FILE ]]; then
                    echo "Template file not exist"
                    exit 1
                fi
                TEMPLATE=$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")
            else
                echo "Template file required"
                exit 1
            fi
            ;;
        --keep-build)
            BUILD_KEEP=true
            ;;
        --keep-source)
            SOURCE_KEEP=true
            ;;
        --devices)
            LIST_DEVICES=true
            ;;
        --simulators)
            LIST_SIMS=true
            ;;
        --help)
            awk '/# HELP_START/{flag=1;next} /# HELP_END/{exit} flag' $0
            exit 0
            ;;
        --version)
            shift
            if [[ $# -eq 0 || "$1" == "--"* ]]; then
                echo "Missing <version> to select"
                exit 1
            fi
            VERSION="$1"
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

echo "=================================="
echo "Blink Shell Build Script"
echo "=================================="
echo "Version: $VERSION"
echo "Source directory: $SOURCE_DIR"
echo ""

# device_search <simulator> <field> <name> <result>
# SIMULATOR: true|false.  false==device
# FIELD: Data field to query
# NAME: Regexp of val to search for
# RESULT: id|list
# Global: BUILD_DIR, CONF_DEBUG, PROJECT_FILE, XCLIST, MIN_PLATFORM
device_search() {

    local SIMULATOR=$1
    local FIELD=$2
    local NAME=$3
    local RESULT=$4

    if [[ ! -f $XCLIST ]]; then
        mkdir -p "$BUILD_DIR"
        xcrun xcdevice list > "$XCLIST"
    fi
    if [[ -z $MIN_PLATFORM ]]; then
        BLINK_DEBUG=$(find_target ${CONF_DEBUG} Blink ${PROJECT_FILE})
        MIN_PLATFORM=$(plist_get ":objects:${BLINK_DEBUG}:buildSettings:IPHONEOS_DEPLOYMENT_TARGET" ${PROJECT_FILE})
        if [[ -z $MIN_PLATFORM ]]; then
            echo "Problem identifying the minimum supported platform in project"
            exit 1
        fi
    fi
    local lookup=$(cat $XCLIST | jq -r \
        --arg simulator "$SIMULATOR" \
        --arg field "$FIELD" \
        --arg name "$NAME" \
        --arg result "$RESULT" \
        --arg min "$MIN_PLATFORM" \
            'sort_by(.operatingSystemVersion) |
            [ .[] |
                select(
                .simulator == ($simulator == "true") and
                (.platform | contains("iphone")) and
                ((.operatingSystemVersion | split(" ") | .[0] | tonumber) >= ($min | tonumber)) and
                (.[$field] | test($name; "i"))
                )
            ] |
            if $result == "id" then
                last | .identifier | select(. != null)
            elif $result == "list" then
                .[] | [.identifier, .operatingSystemVersion, .name ] | @tsv
            else
                .
            end
        ')
    echo "$lookup"
}

# find_plist_entry <field> <regexp> <filter> [<plist>]
find_plist_entry() {
    local FIELD=$1
    local REGEXP=$2
    local FILTER=$3
    local FILE=${4:-$PROJECT_FILE}

    if [[ -n $FILTER ]]; then
        FILTER="and $FILTER"
    fi

    local id=$($PLISTJ "${FILE}" | jq -r \
        ".. | objects | to_entries[] |
        select(((.value.[\"$FIELD\"]? | tostring) | test(\"$REGEXP\"))
        $FILTER) | .key")
    echo $id
}

# find_resource <field> <resource>
# FIELD: Field to search on
# RES: Suffix of value to search on
find_resource() {
    local FIELD=$1
    local RES=$2
    local id=$(find_plist_entry "${FIELD}" ".*${RES}" )
    echo $id
}

# find_target <target> <name>
# TARGET: Debug or Release
# NAME: Name of product
find_target() {
    local TARGET=$1
    local NAME=$2
    local id=$(find_plist_entry "name" "$TARGET" \
        ".value.buildSettings?.PRODUCT_NAME? == \"$NAME\"")
    echo $id
}

# plist_set <resource> <value> [<file>]
# Notes: if it doesnt exist, it will be defined as a string
# RES: Resource tree to set
# VAL: Value to set
# FILE: plist file
plist_set() {
    local RES=$1
    local VAL=$2
    local FILE=${3:-$PROJECT_FILE}
    if $PLIST -c "Print $RES" ${FILE} 2>/dev/null >/dev/null; then
        $PLIST -c "Set $RES $VAL" ${FILE} 2>/dev/null >/dev/null
    else
        $PLIST -c "Add $RES string $VAL" ${FILE} 2>/dev/null >/dev/null
    fi
}

# plist_del <resource> [<file>]
# Notes: if it doesnt exist, the change is ignored
# RES: Resource tree to delete
# FILE: plist file
plist_del() {
    local RES=$1
    local FILE=${2:-$PROJECT_FILE}
    if $PLIST -c "Print $RES" ${FILE} 2>/dev/null >/dev/null; then
        $PLIST -c "Delete $RES" ${FILE} 2>/dev/null >/dev/null
    fi
}

# plist_get <resource> [<file>]
# RES: Resource tree to lookup
# FILE: plist file
plist_get() {
    local RES=$1
    local FILE=${2:-$PROJECT_FILE}
    local RESULT=$($PLIST -c "Print $RES" ${FILE} 2>/dev/null)
    echo $RESULT
}

# Get configuration setting for developer config
# FIELD: The field to lookup
# FILE: developer config file
get_config() {
    local FIELD=$1
    local FILE=${2:-$DEVSETUP}
    local RESULT=$(awk -v field="$FIELD" '!/\/\// && $0 ~ field {print $3}' ${FILE})
    echo $RESULT
}

# Search for existing provisioning profile that match TEAM_ID/BUNDLE_ID
# Depends on global TEAM_ID and BUNDLE_ID
get_profile() {
    if [ -z "$TEAM_ID" -o -z "$BUNDLE_ID" ]; then
        return ""
    fi
    PROFILE=$(grep -l "${TEAM_ID}.${BUNDLE_ID}<" ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision | head -n 1)
    echo $PROFILE
}

# Preflight checks
preflight_checks() {
    local missing=0

    for cmd in git python3 grep sed awk jq plutil xcodebuild $PLIST; do
        if ! command -v $cmd &>/dev/null; then
            echo "Error: $cmd is required but not found."
            missing=1
        fi
    done

    if ! xcode-select -p &> /dev/null; then
        echo "Error: Xcode Command Line Tools not configured. Run xcode-select --install."
        missing=1
    fi

    if ! xcrun --sdk iphoneos --show-sdk-path &> /dev/null; then
        echo "Error: iOS platform content is missing. Install iOS in Xcode > Settings > Platforms."
        missing=1
    fi

    if [[ $DO_SIMULATOR == true ]]; then
        if ! xcrun --sdk iphonesimulator --show-sdk-path &> /dev/null; then
            echo "Error: iOS Simulator platform content is missing."
            echo "Install it in Xcode > Settings > Platforms."
            missing=1
        fi
    fi

    if [ "$missing" -ne 0 ]; then
        exit 1
    fi
}

# Function to fix package dependencies
fix_package_dependencies() {
    echo "Fixing package dependencies..."

    for pkg in "swiftui-cached-async-image 1.9.0" "SwiftCBOR 0.4.0"; do
        array=($pkg)
        resource=$(find_resource "repositoryURL" "${array[0]}")
        if [ -n "$resource" ]; then
            req=":objects:$resource:requirement"
            plist_set "$req:kind" "upToNextMajorVersion" ${PROJECT_FILE}
            plist_set "$req:minimumVersion" "${array[1]}" ${PROJECT_FILE}
            plist_del "$req:branch" ${PROJECT_FILE}
            echo "  Fixed $pkg package"
        else
            echo "  Unable to fix $pkg package"
        fi
    done

    # Clear SPM cache to avoid stale manifests
    rm -rf ~/Library/Caches/org.swift.swiftpm/manifests 2>/dev/null || true
    rm -rf "${XCSHARED}/swiftpm/Package.resolved" 2>/dev/null || true
}

# Function to remove paywall (GPL sideload build)
patch_remove_paywall() {
    echo "Patching: Removing paywall for GPL sideload build..."

    local ENTITLEMENTS_FILE="${SOURCE_DIR}/Blink/Subscriptions/EntitlementsManager.swift"

    if [ -f "$ENTITLEMENTS_FILE" ]; then
        python3 - "$ENTITLEMENTS_FILE" << 'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = fh.read()

def replace_func(name, body_lines):
    pattern = re.compile(rf"\bpublic func {re.escape(name)}\b")
    m = pattern.search(data)
    if not m:
        return data, False

    line_start = data.rfind("\n", 0, m.start()) + 1
    line_end = data.find("\n", m.start())
    if line_end == -1:
        line_end = len(data)
    indent = re.match(r"[ \\t]*", data[line_start:line_end]).group(0)

    brace_open = data.find("{", m.end())
    if brace_open == -1:
        return data, False

    depth = 0
    i = brace_open
    in_string = False
    in_line_comment = False
    in_block_comment = False
    while i < len(data):
        ch = data[i]
        nxt = data[i + 1] if i + 1 < len(data) else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
            i += 1
            continue
        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == "\"":
                in_string = False
            i += 1
            continue

        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        if ch == "\"":
            in_string = True
            i += 1
            continue

        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                brace_close = i
                break
        i += 1
    else:
        return data, False

    inner_indent = indent + "  "
    new_body = "\n".join([inner_indent + line for line in body_lines])
    new_data = data[:brace_open + 1] + "\n" + new_body + "\n" + indent + "}" + data[brace_close + 1:]
    return new_data, True

changed = False
data, did_change = replace_func(
    "currentPlanName",
    [
        "// BLINK_WRAPPER_PATCH",
        "return \"GPL Sideload Build\"",
    ],
)
changed = changed or did_change

data, did_change = replace_func(
    "customerTier",
    [
        "// BLINK_WRAPPER_PATCH",
        "return CustomerTier.Classic",
    ],
)
changed = changed or did_change

data, did_change = replace_func(
    "hasActiveSubscriptions",
    [
        "// BLINK_WRAPPER_PATCH",
        "return true",
    ],
)
changed = changed or did_change

if changed:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(data)
PY

        echo "  Paywall removed (function body replacement)"
    else
        echo "  Warning: EntitlementsManager.swift not found"
    fi
}

# Patch to skip Migrator (uses FileProvider APIs that don't work with sideloading)
patch_skip_migrator() {
    echo "Patching: Skipping Migrator for sideload build..."

    local APP_DELEGATE="${SOURCE_DIR}/Blink/AppDelegate.m"

    if [ -f "$APP_DELEGATE" ]; then
        # Comment out [Migrator perform]; call
        if grep -q '^\s*\[Migrator perform\];' "$APP_DELEGATE" 2>/dev/null; then
            sed -i '' 's/^\([[:space:]]*\)\[Migrator perform\];/\1\/\/ [Migrator perform]; \/\/ Disabled for sideload - uses FileProvider APIs/' "$APP_DELEGATE"
            echo "  Migrator disabled in AppDelegate.m"
        elif grep -q '// \[Migrator perform\];' "$APP_DELEGATE" 2>/dev/null; then
            echo "  Migrator already disabled"
        else
            echo "  Warning: Could not find Migrator call in AppDelegate.m"
        fi
    else
        echo "  Warning: AppDelegate.m not found"
    fi
}

# Patch to guard FileProvider APIs when extensions are missing (sideload)
patch_fileprovider_sideload() {
    echo "Patching: Guarding FileProvider APIs for sideload build..."

    local FP_DOMAIN="${SOURCE_DIR}/Settings/Model/FileProviderDomain.swift"
    local MIGRATION_FILE="${SOURCE_DIR}/Blink/Migrator/1810Migration.swift"
    local APP_DELEGATE="${SOURCE_DIR}/Blink/AppDelegate.m"

    if [ -f "$FP_DOMAIN" ]; then
        python3 - "$FP_DOMAIN" << 'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = fh.read()

changed = False

if "FileProviderAvailability.isAvailable" not in data:
    pattern = re.compile(r'(^[ \t]*)@objc static func syncWithBKHosts\(\) \{', re.M)
    match = pattern.search(data)
    if match:
        indent = match.group(1)
        inner_indent = indent + "  "
        guard_block = (
            "\n"
            f"{inner_indent}guard FileProviderAvailability.isAvailable else {{\n"
            f"{inner_indent}  return\n"
            f"{inner_indent}}}\n"
        )
        data = data[:match.end()] + guard_block + data[match.end():]
        changed = True

if "final class FileProviderAvailability" not in data:
    availability_block = (
        "\n\n"
        "@objc final class FileProviderAvailability: NSObject {\n"
        "  @objc static let isAvailable: Bool = {\n"
        "    guard let pluginsURL = Bundle.main.builtInPlugInsURL else {\n"
        "      return false\n"
        "    }\n"
        "    guard let pluginURLs = try? FileManager.default.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil) else {\n"
        "      return false\n"
        "    }\n\n"
        "    for url in pluginURLs where url.pathExtension == \"appex\" {\n"
        "      guard\n"
        "        let bundle = Bundle(url: url),\n"
        "        let extensionInfo = bundle.infoDictionary?[\"NSExtension\"] as? [String: Any],\n"
        "        let pointIdentifier = extensionInfo[\"NSExtensionPointIdentifier\"] as? String\n"
        "      else {\n"
        "        continue\n"
        "      }\n\n"
        "      if pointIdentifier == \"com.apple.fileprovider-nonui\" ||\n"
        "         pointIdentifier == \"com.apple.fileprovider\" ||\n"
        "         pointIdentifier == \"com.apple.fileprovider-replicated\" {\n"
        "        return true\n"
        "      }\n"
        "    }\n\n"
        "    return false\n"
        "  }()\n"
        "}\n"
    )
    data = data.rstrip() + availability_block
    changed = True

if changed:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(data)
PY
        echo "  FileProviderDomain guards applied"
    else
        echo "  Warning: FileProviderDomain.swift not found"
    fi

    if [ -f "$MIGRATION_FILE" ]; then
        python3 - "$MIGRATION_FILE" << 'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = fh.read()

if "FileProviderAvailability.isAvailable" in data:
    sys.exit(0)

pattern = re.compile(r'(^[ \t]*)private func deleteFileProviderStorage\(\) \{', re.M)
match = pattern.search(data)
if not match:
    sys.exit(0)

indent = match.group(1)
inner_indent = indent + "  "
guard_block = (
    "\n"
    f"{inner_indent}guard FileProviderAvailability.isAvailable else {{\n"
    f"{inner_indent}  return\n"
    f"{inner_indent}}}\n"
)

data = data[:match.end()] + guard_block + data[match.end():]
with open(path, "w", encoding="utf-8") as fh:
    fh.write(data)
PY
        echo "  Migrator FileProvider guard applied"
    else
        echo "  Warning: 1810Migration.swift not found"
    fi

    if [ -f "$APP_DELEGATE" ]; then
        python3 - "$APP_DELEGATE" << 'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = fh.read()

if "FileProviderAvailability isAvailable" in data:
    sys.exit(0)

lines = data.splitlines(keepends=True)
for idx, line in enumerate(lines):
    if "_NSFileProviderManager syncWithBKHosts" in line:
        indent = re.match(r"[ \t]*", line).group(0)
        lines[idx:idx + 1] = [
            f"{indent}if ([FileProviderAvailability isAvailable]) {{\n",
            f"{indent}  [_NSFileProviderManager syncWithBKHosts];\n",
            f"{indent}}}\n",
        ]
        break
else:
    sys.exit(0)

with open(path, "w", encoding="utf-8") as fh:
    fh.write("".join(lines))
PY
        echo "  AppDelegate FileProvider guard applied"
    else
        echo "  Warning: AppDelegate.m not found"
    fi
}

# Function to fix get_resources.sh for repeated runs
fix_get_resources_script() {
    local SCRIPT_FILE="${SOURCE_DIR}/get_resources.sh"

    if [ -f "$SCRIPT_FILE" ] && grep -q 'mv runtime/\*' "$SCRIPT_FILE" 2>/dev/null; then
        echo "Fixing get_resources.sh for repeated runs..."
        sed -i '' 's/unzip runtime.zip && mv runtime\/\* .\/ && rm runtime.zip/unzip -q -o runtime.zip \&\& cp -rf runtime\/* .\/ \&\& rm -rf runtime runtime.zip/' "$SCRIPT_FILE"
    fi
}

fix_team_id() {
    echo "Fixing TEAM_ID in project"
    gsed -i 's/A2H2CL32AG/${TEAM_ID}/g' ${PROJECT_FILE}
}

# Inject SideloadFix.dylib from https://github.com/waruhachi/SideloadFix
# Fixes App Group containers and keychain access for sideloaded apps
inject_sideload_fix() {
    local APP_BUNDLE="$1"
    local APP_NAME=$(basename "$APP_BUNDLE" .app)
    local FRAMEWORKS_DIR="$APP_BUNDLE/Frameworks"
    local DYLIB_URL="https://github.com/waruhachi/SideloadFix/releases/download/release/SideloadFix.dylib"
    local DYLIB_PATH="${SCRIPT_DIR}/.cache/SideloadFix.dylib"
    local INSERT_DYLIB="${SCRIPT_DIR}/.cache/insert_dylib"

    echo "Injecting SideloadFix.dylib..."
    mkdir -p "${SCRIPT_DIR}/.cache"

    # Download SideloadFix.dylib if not cached
    if [ ! -f "$DYLIB_PATH" ]; then
        echo "  Downloading SideloadFix.dylib..."
        curl -sL "$DYLIB_URL" -o "$DYLIB_PATH"
    fi

    # Build insert_dylib if not cached
    if [ ! -f "$INSERT_DYLIB" ]; then
        echo "  Building insert_dylib..."
        local TEMP_DIR=$(mktemp -d)
        git clone --depth 1 https://github.com/tyilo/insert_dylib.git "$TEMP_DIR" 2>/dev/null
        clang -o "$INSERT_DYLIB" "$TEMP_DIR/insert_dylib/main.c" -framework Foundation 2>/dev/null
        rm -rf "$TEMP_DIR"
    fi

    # Copy dylib to Frameworks
    mkdir -p "$FRAMEWORKS_DIR"
    cp "$DYLIB_PATH" "$FRAMEWORKS_DIR/"

    # Inject load command
    chmod +x "$INSERT_DYLIB"
    "$INSERT_DYLIB" --strip-codesig --inplace \
        "@executable_path/Frameworks/SideloadFix.dylib" \
        "$APP_BUNDLE/$APP_NAME" 2>/dev/null || true

    echo "  Injected SideloadFix.dylib"
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

    # Check for existing source tree
    if [ -d "$SOURCE_DIR" ]; then

        # Do Update
        if [[ $SOURCE_UPDATE == true ]]; then
            cd "$SOURCE_DIR"

            echo "Fetching latest changes..."
            git fetch --all --tags

            echo "Checking out $VERSION..."
            git checkout "$VERSION"
            git submodule update --init --recursive
            cd ..

        # Check for overwrite
        elif [[ $SOURCE_OVERWRITE == true ]]; then
            echo "Removing existing source directory..."
            rm -rf "$SOURCE_DIR"

        # Use existing
        else
            echo "Using existing source directory."
            if [[ -n $TEMPLATE ]]; then
                echo "Using provided developer config..."
                cp "${TEMPLATE}" "${DEVSETUP}"
            fi
            return 0

        fi
    fi

    # Clone repo
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "Cloning Blink repository (version: $VERSION)..."
        git clone --recursive --branch "$VERSION" "$BLINK_REPO" "$SOURCE_DIR"
    fi

    cd "$SOURCE_DIR"

    echo "Running framework setup..."
    ./get_frameworks.sh

    fix_get_resources_script
    echo "Running resource setup..."
    ./get_resources.sh

    if [[ -n $TEMPLATE ]]; then
        echo "Using provided developer config..."
        cp "${TEMPLATE}" "${DEVSETUP}"

    elif [ ! -f "developer_setup.xcconfig" ]; then
        echo "Creating developer_setup.xcconfig from template..."
        cp template_setup.xcconfig developer_setup.xcconfig
    fi

    # Reset XCLIST
    rm -f "${XCLIST}"

    echo "Cleaning Xcode workspace..."
    rm -rf "${XCSHARED}"

    fix_package_dependencies
    fix_team_id
    patch_remove_paywall
    patch_skip_migrator
    patch_fileprovider_sideload
    create_sideload_entitlements

    resolve_packages

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
    rm -f "${BUILD_LOG}"
    echo $* | tee -a "${BUILD_LOG}"
    if command -v xcpretty &> /dev/null; then
        "$@" 2>&1 | xcpretty | tee -a "${BUILD_LOG}"
    else
        "$@" 2>&1 | tee -a "${BUILD_LOG}"
    fi
}

# Function to build
build_app() {
    local EXTRA_FLAGS="ENABLE_DEBUG_DYLIB=NO"
    local BUILD_CMDS="build"
    local DEST="generic/platform=iOS"
    local CONF="${CONF_DEBUG}"
    local APP_NAME="Blink"
    local APP="${APP_NAME}.app"
    local DIST=""
    local SIGNED=false
    local APP_FILTER=".*"
    local OUT_DIR=""
    local PLATFORM="iphoneos"


    echo ""
    echo "Building Blink Shell..."
    echo ""

    mkdir -p "${BUILD_DIR}"

    # Setup simulator and device install
    if [[ $DO_SIMULATOR == true ||$DO_INSTALL == true ]]; then
        if [ -n "$DEVICE" ]; then

            # Identifier search
            if [[ ($DO_SIMULATOR == true && $DEVICE =~ $PAT_UUID) ||\
                    ($DO_INSTALL == true && $DEVICE =~ $PAT_DEVID) ]]; then
                DEVICE_ID=$(device_search "$DO_SIMULATOR" "identifier" "$DEVICE" "id")

            # Name search
            else
                ESCAPED=$(echo "$DEVICE" | gsed 's/[.()*]/\\&/g')
                DEVICE_ID=$(device_search "$DO_SIMULATOR" "name" "$ESCAPED" "id")
            fi
        fi

        # General Search for IOS device
        if [[ -z $DEVICE_ID ]]; then
            DEVICE_ID=$(device_search "$DO_SIMULATOR" "platform" ".*iphone.*" "id")
        fi

        # Create Simulator
        if [[ -z $DEVICE_ID ]]; then
            if [[ $DO_SIMULATOR == true ]]; then
                echo "No suitable iPhone simulator found. Creating one..."
                DEVICE_ID=$(xcrun simctl create "iPhone 15" "com.apple.CoreSimulator.SimDeviceType.iPhone-15")
            else
                echo "Error: No iOS device connected. Please connect a device and try again."
                exit 1
            fi
        fi

        # Setup build
        if [[ $DO_SIMULATOR == true ]]; then
            PLATFORM="iphonesimulator"
            xcrun simctl boot "${DEVICE_ID}" 2>/dev/null || true
        else
            SIGNED=true
            EXTRA_FLAGS="-allowProvisioningUpdates ${EXTRA_FLAGS}"
        fi
        OUT_DIR="DerivedData/Build/Products/${CONF}-${PLATFORM}"

        echo "Selected device: $DEVICE_ID"
        DEST="id=$DEVICE_ID"

    # Setup archive
    elif [[ $DO_ARCHIVE == true ]]; then
        CONF="${CONF_RELEASE}"
        SIGNED=true
        APP="${APP_NAME}-${VERSION}.xcarchive"
        DIST="${OUTPUT_DIR}/${APP}"
        EXTRA_FLAGS="-archivePath ${BUILD_DIR}/${APP}"
        BUILD_CMDS="archive"

    # Setup unsigned ipa
    elif [[ $DO_UNSIGNED_IPA == true ]]; then
        CONF="${CONF_RELEASE}"
        IPA="${APP_NAME}-unsigned-${VERSION}.ipa"
        DIST="${OUTPUT_DIR}/${IPA}"
        OUT_DIR="DerivedData/Build/Products/${CONF}-${PLATFORM}"

        EXTRA_FLAGS="
            CODE_SIGN_IDENTITY=\"-\"
            CODE_SIGNING_REQUIRED=NO
            CODE_SIGNING_ALLOWED=NO
            CODE_SIGN_ENTITLEMENTS=\"${SOURCE_DIR}/Blink/Blink-sideload.entitlements\"
            DEAD_CODE_STRIPPING=NO
            ENABLE_PREVIEWS=NO"

    elif [[ $DO_SIGNED_IPA == true ]]; then
        CONF="${CONF_RELEASE}"
        IPA="${APP_NAME}-signed-${VERSION}.ipa"
        DIST="${OUTPUT_DIR}/${IPA}"
        OUT_DIR="DerivedData/Build/Products/${CONF}-${PLATFORM}"
        SIGNED=true
    fi

    # Load Build identifiers
    TEAM_ID=$(get_config "TEAM_ID" ${DEVSETUP})
    BUNDLE_ID=$(get_config "BUNDLE_ID" ${DEVSETUP})
    if [ -z "$TEAM_ID" -o -z "$BUNDLE_ID" ]; then
        echo "Unable to locate TEAM_ID or BUNDLE_ID..."
        exit 1
    fi
    echo "Building for ${TEAM_ID}/${BUNDLE_ID}..."

    if [[ $SIGNED == true ]]; then
        echo "Checking provisioning for signed build"
        PROFILE=$(get_profile ${DEVSETUP})
        if [[ -z $PROFILE ]]; then
            echo "Missing provisioning profile for signed build"
            exit 1
        fi
        echo "Identified profile ${PROFILE##*/}"
        security cms -D -i "$PROFILE" > $BUILD_DIR/profile
        CHK=$(plist_get ":Entitlements:com.apple.developer.web-browser" $BUILD_DIR/profile)
        if [[ -z $CHK ]]; then
            echo "Removing web-browser entitlement"
            plist_del "com.apple.developer.web-browser" ${SOURCE_DIR}/Blink/Blink.entitlements
        fi
    fi

    if [[ $DO_CLEAN == true ]]; then
        BUILD_CMDS="clean ${BUILD_CMDS}"
    fi

    run_xcodebuild xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONF" \
        -destination "$DEST" \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        -skipPackagePluginValidation \
        -skipMacroValidation \
        $EXTRA_FLAGS \
        $BUILD_CMDS

    # Locate Generated Build
    APP_PATH=$(find "${BUILD_DIR}/${OUT_DIR}" -name "${APP}")
    if [[ -z $APP_PATH ]]; then
        echo "Unable to locate ${APP} build"
        exit 1
    fi
    echo "Build: ${APP_PATH}"

    # Post-build steps
    if [[ $DO_SIMULATOR == true ]]; then
        echo "Installing to simulator: ${DEVICE_ID}"
        open -a Simulator
        sleep 2
        xcrun simctl install "${DEVICE_ID}" "${APP_PATH}"
        if [ $? -ne 0 ]; then
            echo "Problem installing build to simulator"
            exit 1
        fi
        xcrun simctl launch "${DEVICE_ID}" "${BUNDLE_ID}"
        if [ $? -ne 0 ]; then
            echo "Problem launching build in simulator"
            exit 1
        fi

        echo "Blink launched in simulator"

    elif [[ $DO_INSTALL == true ]]; then
        echo "Installing to device: ${DEVICE_ID}"
        xcrun devicectl device install app \
            --device "${DEVICE_ID}" "${APP_PATH}"
        if [ $? -ne 0 ]; then
            echo "Problem installing build"
            exit 1
        fi

        echo "Blink launched on device"

    elif [[ $DO_UNSIGNED_IPA == true || $DO_SIGNED_IPA == true ]]; then
        PAYLOAD_DIR="${BUILD_DIR}/Payload"
        rm -rf "$PAYLOAD_DIR"
        mkdir -p "$PAYLOAD_DIR"

        cp -r "${APP_PATH}" "${PAYLOAD_DIR}/"

        if [[ $DO_UNSIGNED_IPA == true ]]; then

            # Remove app extensions that require entitlements incompatible with sideloading
            echo "Removing incompatible app extensions..."
            rm -rf "${PAYLOAD_DIR}/Blink.app/PlugIns"

            # Inject SideloadFix.dylib for App Group and keychain fixes
            inject_sideload_fix "${PAYLOAD_DIR}/Blink.app"

        fi

        # Create .ipa (which is just a zip file)
        (cd "${BUILD_DIR}" && zip -r -q "${IPA}" Payload)
        APP_PATH="${BUILD_DIR}/${IPA}"

    fi

    # Store distribution file
    if [[ -n $DIST ]]; then
        mkdir -p "$OUTPUT_DIR"
        rm -fr "${DIST}"
        if [[ $BUILD_KEEP = true ]]; then
            cp -R "$APP_PATH" "$DIST"
        else
            mv "$APP_PATH" "$DIST"
        fi
        echo "Created: ${DIST}"
    fi
}

# Main execution
preflight_checks
setup_repository

# Handle --setup-only
if [[ $SETUP_ONLY == true ]]; then
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

# Handle --devices
elif [[ $LIST_DEVICES == true ]]; then
    devices=$(device_search "false" "name" ".*" "list")
    echo "$devices"
    exit 0

# Handle --simulators
elif [[ $LIST_SIMS == true ]]; then
    sims=$(device_search "true" "name" ".*" "list")
    echo "$sims"
    exit 0

fi

# Build App
mkdir -p "$BUILD_DIR"
build_app

# Clean up
if [[ $BUILD_KEEP == false ]]; then
    echo ""
    echo "Cleaning build output..."
    rm -rf "$BUILD_DIR"
fi
if [[ $SOURCE_KEEP == false ]]; then
    echo "Cleaning source checkout..."
    rm -rf "$SOURCE_DIR"
fi
echo ""
echo "=================================="
echo "Build complete!"
echo "=================================="
echo ""
