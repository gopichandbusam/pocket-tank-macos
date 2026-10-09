#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
command -v sdl2-config >/dev/null || { echo "Install SDL2 development files with: brew install sdl2" >&2; exit 1; }
if [ ! -d sim/lvgl ]; then
  git clone --depth 1 --branch v9.2.2 https://github.com/lvgl/lvgl.git sim/lvgl
fi
make -C sim -j"$(sysctl -n hw.ncpu)"
make -C sim check
python3 mac/tests/test_persistence.py
python3 mac/tests/test_advisor_mailbox.py
python3 mac/package.py
python3 mac/build_uninstaller.py
python3 mac/create_dmg.py --uninstaller 'dist/Uninstall Pocket Tank.app'
echo "Installer: $PROJECT_ROOT/dist/Pocket Tank.dmg"
