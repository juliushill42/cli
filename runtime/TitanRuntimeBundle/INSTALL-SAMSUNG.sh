#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HOME/titan-runtime"
STATE="$HOME/.titanu"
MESH="$HOME/.wecanmesh"

echo "=========================================="
echo " TITAN SAMSUNG — NODE INSTALL"
echo "=========================================="

case "$(uname -m)" in
  aarch64|arm64) ;;
  *)
    echo "FATAL: this runtime bundle is ARM64."
    exit 1
    ;;
esac

command -v pkg >/dev/null || {
    echo "FATAL: run this in native Termux."
    exit 1
}

echo "[1/8] Runtime dependencies"

PKGS=()

command -v postgres >/dev/null 2>&1 || PKGS+=(postgresql)
command -v initdb   >/dev/null 2>&1 || PKGS+=(postgresql)
command -v pg_ctl   >/dev/null 2>&1 || PKGS+=(postgresql)
command -v curl     >/dev/null 2>&1 || PKGS+=(curl)
command -v python3  >/dev/null 2>&1 || PKGS+=(python)

if [ "${#PKGS[@]}" -gt 0 ]; then
    pkg install -y "${PKGS[@]}"
fi

echo "[2/8] Preserving existing Samsung environment"

if [ -d "$ROOT" ]; then
    BACKUP="$HOME/titan-runtime.backup.$(date +%s)"
    mv "$ROOT" "$BACKUP"
    echo "Existing Titan runtime backed up: $BACKUP"
fi

mkdir -p \
  "$ROOT/bin" \
  "$ROOT/target/release" \
  "$ROOT/data" \
  "$ROOT/logs" \
  "$ROOT/run" \
  "$STATE" \
  "$MESH"

cp -a "$SRC/payload/." "$ROOT/"

chmod 700 \
  "$ROOT/bin/titand" \
  "$ROOT/bin/titanctl" \
  "$ROOT/target/release/telecom-userland-daemon"

echo "[3/8] Creating independent Samsung identity"

if [ ! -s "$STATE/device-id" ]; then
    UUID="$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-16 | tr '[:lower:]' '[:upper:]')"
    printf 'TITAN-%s\n' "$UUID" > "$STATE/device-id"
fi

printf '%s\n' 'hs.wecanjuschill.net' > "$STATE/control"

cat > "$MESH/node.env" <<EOF
TITAN_DEVICE_ID=$(cat "$STATE/device-id")
TITAN_CONTROL=hs.wecanjuschill.net
TITAN_ARCH=$(uname -m)
EOF

echo "Device : $(cat "$STATE/device-id")"
echo "Control: hs.wecanjuschill.net"

echo "[4/8] Configuring isolated PostgreSQL"

PGDATA="$ROOT/data/postgres"

if [ ! -f "$PGDATA/PG_VERSION" ]; then
    mkdir -p "$PGDATA"
    chmod 700 "$PGDATA"
    initdb -D "$PGDATA" --auth-local=trust --auth-host=trust >/dev/null
fi

if ! grep -q '^listen_addresses.*127\.0\.0\.1' "$PGDATA/postgresql.conf"; then
cat >> "$PGDATA/postgresql.conf" <<EOF

# Titan Samsung node
listen_addresses = '127.0.0.1'
port = 5432
EOF
fi

echo "[5/8] Installing supervisors"

cat > "$ROOT/titand-supervisor.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u

ROOT="$HOME/titan-runtime"
mkdir -p "$ROOT/logs" "$ROOT/run"

while true; do
    "$ROOT/bin/titand" \
      --db "$ROOT/data/control" \
      --listen 127.0.0.1:8787 \
      >>"$ROOT/logs/titand.log" 2>&1 &

    PID=$!
    echo "$PID" > "$ROOT/run/titand.pid"

    wait "$PID"
    RC=$?

    echo "[$(date)] titand exited rc=$RC" \
      >>"$ROOT/logs/titand-supervisor.log"

    sleep 2
done
EOF

chmod 700 "$ROOT/titand-supervisor.sh"

cat > "$ROOT/start.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -u

ROOT="$HOME/titan-runtime"
PGDATA="$ROOT/data/postgres"

mkdir -p "$ROOT/logs" "$ROOT/run" "$ROOT/data/control"

echo "=== TITAN NODE START ==="

# PostgreSQL
if pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
    echo "[✓] PostgreSQL already running"
else
    pg_ctl \
      -D "$PGDATA" \
      -l "$ROOT/logs/postgres.log" \
      start >/dev/null 2>&1 || true

    sleep 2

    if pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
        echo "[✓] PostgreSQL :5432"
    else
        echo "[✗] PostgreSQL"
        tail -30 "$ROOT/logs/postgres.log" 2>/dev/null
    fi
fi

# Titan control
python3 - <<'PY' >/dev/null 2>&1
import socket,sys
s=socket.socket(); s.settimeout(.5)
sys.exit(0 if s.connect_ex(("127.0.0.1",8787)) == 0 else 1)
PY

if [ $? -ne 0 ]; then
    if [ -f "$ROOT/run/titand-supervisor.pid" ]; then
        OLD="$(cat "$ROOT/run/titand-supervisor.pid" 2>/dev/null)"
        kill -0 "$OLD" 2>/dev/null || rm -f "$ROOT/run/titand-supervisor.pid"
    fi

    if [ ! -f "$ROOT/run/titand-supervisor.pid" ]; then
        nohup "$ROOT/titand-supervisor.sh" \
          >"$ROOT/logs/titand-supervisor.out" 2>&1 &
        echo "$!" > "$ROOT/run/titand-supervisor.pid"
    fi
fi

sleep 2

# Telecom
if ! pgrep -f "$ROOT/target/release/telecom-userland-daemon" >/dev/null 2>&1; then
    (
      cd "$ROOT"
      nohup "$ROOT/target/release/telecom-userland-daemon" \
        >"$ROOT/logs/telecom.log" 2>&1 &
      echo "$!" > "$ROOT/run/telecom.pid"
    )
fi

sleep 2

exec "$ROOT/status.sh"
EOF

chmod 700 "$ROOT/start.sh"

cat > "$ROOT/stop.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set +e

ROOT="$HOME/titan-runtime"

for name in telecom titand titand-supervisor; do
    F="$ROOT/run/$name.pid"
    if [ -f "$F" ]; then
        PID="$(cat "$F" 2>/dev/null)"
        [ -n "$PID" ] && kill "$PID" 2>/dev/null
        rm -f "$F"
    fi
done

pg_ctl -D "$ROOT/data/postgres" stop -m fast >/dev/null 2>&1 || true

echo "Titan Samsung node stopped."
EOF

chmod 700 "$ROOT/stop.sh"

cat > "$ROOT/status.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

ROOT="$HOME/titan-runtime"
DEVICE="$(cat "$HOME/.titanu/device-id" 2>/dev/null || echo UNKNOWN)"

echo
echo "=========================================="
echo " TITAN SAMSUNG — LIVE STATUS"
echo "=========================================="
echo "Device : $DEVICE"
echo "Control: hs.wecanjuschill.net"
echo "Arch   : $(uname -m)"
echo

python3 - <<'PY'
import socket

for name,port in [
    ("Titan control",8787),
    ("PostgreSQL",5432),
]:
    s=socket.socket()
    s.settimeout(.5)
    ok=s.connect_ex(("127.0.0.1",port)) == 0
    s.close()
    print(f"{'[✓]' if ok else '[✗]'} {name:<22} :{port}")
PY

if pgrep -f "$ROOT/target/release/telecom-userland-daemon" >/dev/null 2>&1; then
    echo "[✓] Sovereign telecom daemon"
else
    echo "[✗] Sovereign telecom daemon"
fi

echo
echo "Capabilities:"
for c in rustc cargo go python3 node clang cmake git ssh; do
    if command -v "$c" >/dev/null 2>&1; then
        printf '  [✓] %s\n' "$c"
    else
        printf '  [ ] %s\n' "$c"
    fi
done

[ -d "$HOME/llama.cpp" ] &&
    echo "  [✓] llama.cpp"

[ -d "$HOME/android-sdk" ] &&
    echo "  [✓] Android SDK"

echo
echo "Processes:"
pgrep -af 'titand|telecom-userland-daemon|postgres' 2>/dev/null || true
EOF

chmod 700 "$ROOT/status.sh"

echo "[6/8] Installing Titan commands"

for cmd in titan titan-start titan-stop titanctl; do
    if [ -e "$PREFIX/bin/$cmd" ] && [ ! -L "$PREFIX/bin/$cmd" ]; then
        cp "$PREFIX/bin/$cmd" \
           "$PREFIX/bin/$cmd.pre-titan-node.$(date +%s)"
    fi
done

cat > "$PREFIX/bin/titan" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

ROOT="$HOME/titan-runtime"

case "${1:-status}" in
    start)
        exec "$ROOT/start.sh"
        ;;
    stop)
        exec "$ROOT/stop.sh"
        ;;
    status)
        exec "$ROOT/status.sh"
        ;;
    id)
        cat "$HOME/.titanu/device-id"
        ;;
    health)
        curl -sS -L http://127.0.0.1:8787/health/
        ;;
    logs)
        case "${2:-control}" in
            control|titand) tail -n 100 -f "$ROOT/logs/titand.log" ;;
            telecom) tail -n 100 -f "$ROOT/logs/telecom.log" ;;
            postgres) tail -n 100 -f "$ROOT/logs/postgres.log" ;;
            *) echo "usage: titan logs {control|telecom|postgres}" ;;
        esac
        ;;
    *)
        echo "Titan commands:"
        echo "  titan start"
        echo "  titan stop"
        echo "  titan status"
        echo "  titan health"
        echo "  titan id"
        echo "  titan logs control"
        echo "  titan logs telecom"
        echo "  titan logs postgres"
        ;;
esac
EOF

chmod 755 "$PREFIX/bin/titan"

cat > "$PREFIX/bin/titan-start" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
exec "$HOME/titan-runtime/start.sh"
EOF

cat > "$PREFIX/bin/titan-stop" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
exec "$HOME/titan-runtime/stop.sh"
EOF

chmod 755 "$PREFIX/bin/titan-start" "$PREFIX/bin/titan-stop"

ln -sf "$ROOT/bin/titanctl" "$PREFIX/bin/titanctl"

echo "[7/8] Starting Samsung Titan node"

"$ROOT/start.sh"

echo
echo "[8/8] Verification"

echo "--- CONTROL HEALTH ---"
curl -sS -L --max-time 3 \
  http://127.0.0.1:8787/health/ 2>/dev/null || true
echo

echo "--- DATABASE ---"
pg_isready -h 127.0.0.1 -p 5432 || true

echo "--- TELECOM LOG ---"
tail -20 "$ROOT/logs/telecom.log" 2>/dev/null || true

echo
echo "=========================================="
echo " TITAN INSTALLED ON SAMSUNG"
echo "=========================================="
echo
echo "Run:"
echo "  titan status"
echo "  titan health"
echo "  titan id"
