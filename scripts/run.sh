#!/bin/bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd -- "$script_directory/.." && pwd)"
configuration="${1:-debug}"

"$script_directory/build-app.sh" "$@"
open "$project_directory/build/$configuration/Chop.app"
