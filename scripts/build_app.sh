#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
app_dir="$project_dir/dist/SnapCompanion.app"
derived_data="$project_dir/.build/tuist"
signing_identity=${SNAPSYNC_SIGNING_IDENTITY:--}

cd "$project_dir"
mise exec -- tuist generate --no-open
xcodebuild \
    -workspace SnapCompanion.xcworkspace \
    -scheme SnapCompanionApp \
    -configuration Release \
    -destination "platform=macOS" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

rm -rf "$app_dir"
mkdir -p "$project_dir/dist"
ditto "$derived_data/Build/Products/Release/SnapCompanion.app" "$app_dir"

ext_dir="$app_dir/Contents/Library/SystemExtensions/br.com.anykey.SnapSync.proxy.systemextension"
app_profile="$project_dir/Packaging/profiles/SnapCompanion.provisionprofile"
proxy_profile="$project_dir/Packaging/profiles/SnapCompanionProxy.provisionprofile"

# The Network Extension entitlement is restricted: even for Developer ID the
# app and system extension must embed a provisioning profile that carries it.
if [[ -f "$app_profile" && -f "$proxy_profile" ]]; then
    cp "$app_profile" "$app_dir/Contents/embedded.provisionprofile"
    cp "$proxy_profile" "$ext_dir/Contents/embedded.provisionprofile"
elif [[ "$signing_identity" != "-" ]]; then
    print -u2 "Missing provisioning profiles in Packaging/profiles/ (see README); the system extension will not load."
    exit 1
fi

plutil -lint "$app_dir/Contents/Info.plist"
# Sign inside-out: system extension first, then the app.
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - "$ext_dir"
    codesign --force --sign - "$app_dir"
else
    codesign --force --options runtime --timestamp \
        --entitlements "$project_dir/Packaging/SnapCompanionProxy.entitlements" \
        --sign "$signing_identity" "$ext_dir"
    codesign --force --options runtime --timestamp \
        --entitlements "$project_dir/Packaging/SnapCompanion.entitlements" \
        --sign "$signing_identity" "$app_dir"
fi
codesign --verify --deep --strict --verbose=2 "$app_dir"

print "Built $app_dir"
print "Signed with $signing_identity"
