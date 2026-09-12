#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
source_app="${project_root}/DerivedData/Build/Products/Release/CyberFly.app"
destination_root="/Users/dadudu/Applications"
destination_app="${destination_root}/CyberFly.app"
timestamp="$(date +%Y%m%d-%H%M%S)"

"${script_dir}/build-release.sh"
mkdir -p "${destination_root}"

if [[ -d "${destination_app}" ]]; then
  mv "${destination_app}" "${destination_root}/CyberFly-${timestamp}.app.disabled"
fi

ditto "${source_app}" "${destination_app}"
pluginkit -a "${destination_app}/Contents/PlugIns/CyberFlyWidget.appex"
open "${destination_app}"

print "Installed: ${destination_app}"

