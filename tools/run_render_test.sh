#!/bin/sh
# Mede o custo do MapView fora do Studio: ./tools/run_render_test.sh
cd "$(dirname "$0")/.."
LUAU=${LUAU:-/c/Users/andra/Desktop/HerosGotHuman/tools/luau/luau.exe}
OUT=$(mktemp -d)/bundle.luau
{ echo "local Config = (function()"; cat src/shared/Config.luau; echo "end)()"
  echo "local WorldMap = (function()"; cat src/shared/WorldMap.luau; echo "end)()"
  echo "local CivData = (function()"; cat src/shared/CivData.luau; echo "end)()"
  echo "local Sim = (function()"; cat src/shared/Sim.luau; echo "end)()"
  echo "local Civ = (function()"; cat src/shared/Civ.luau; echo "end)()"
  echo "Civ.install(Sim)"
  sed -n '1,/^local geo = Sim.new/p' tools/render_test.luau | sed '$d'
  echo "local MapView = (function()"; cat src/client/MapView.luau; echo "end)()"
  echo "local DetailView = (function()"; cat src/client/DetailView.luau; echo "end)()"
  sed -n '/^local geo = Sim.new/,$p' tools/render_test.luau; } > "$OUT"
"$LUAU" "$OUT"
