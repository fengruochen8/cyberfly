#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
xcode_developer_dir="/Applications/Xcode.app/Contents/Developer"
derived_data_path="${project_root}/DerivedData"
app_path="${derived_data_path}/Build/Products/Release/CyberFly.app"

export DEVELOPER_DIR="${xcode_developer_dir}"
export CLANG_MODULE_CACHE_PATH="/private/tmp/cyberfly-xcode-module-cache"

"${xcode_developer_dir}/usr/bin/xcodebuild" \
  -quiet \
  -project "${project_root}/CyberFly.xcodeproj" \
  -scheme CyberFly \
  -configuration Release \
  -derivedDataPath "${derived_data_path}" \
  CODE_SIGNING_ALLOWED=NO \
  build

codesign --force --sign - "${app_path}/Contents/Frameworks/CyberFlyCore.framework"
codesign --force --sign - "${app_path}/Contents/Frameworks/CyberFlySimulation.framework"
codesign --force --sign - \
  --entitlements "${project_root}/Support/CyberFlyWidget.entitlements" \
  "${app_path}/Contents/PlugIns/CyberFlyWidget.appex"
codesign --force --sign - "${app_path}"
codesign --verify --deep --strict --verbose=2 "${app_path}"

print "Built and verified: ${app_path}"

