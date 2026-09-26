#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"

mkdir -p "$BIN"

ln -sfn "$ROOT/titan-cli" "$BIN/titan-cli"
ln -sfn "$ROOT/titan-cli" "$BIN/Titan"

echo "Installed:"
echo "  $BIN/titan-cli"
echo "  $BIN/Titan"
echo
"$BIN/titan-cli" help
