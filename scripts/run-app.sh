#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT_DIR/scripts/build-app.sh" debug
/usr/bin/open "$ROOT_DIR/dist/Exnano Fabric.app"
