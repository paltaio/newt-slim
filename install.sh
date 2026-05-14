#!/bin/sh
# newt-slim installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh | sh -s -- --name newt-palta
#   curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh | sh -s -- --name newt-palta --update
set -eu

REPO=paltaio/newt-slim
BIN=/usr/bin/newt
ETC_DIR=/etc/newt

NAME=newt
TAG=
UPDATE=0
NO_UPX=0

usage() {
    cat <<EOF
install.sh [--name NAME] [--tag TAG] [--update] [--no-upx]

  --name NAME   Service/instance name (default: newt). Run multiple instances
                by using a unique name per Pangolin site.
  --tag TAG     Release tag (default: latest, e.g. 1.12.5).
  --update      Re-prompt for credentials and overwrite the env file.
  --no-upx      Use the uncompressed binary.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --name) NAME="$2"; shift 2 ;;
        --tag) TAG="$2"; shift 2 ;;
        --update) UPDATE=1; shift ;;
        --no-upx) NO_UPX=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$NAME" in
    ''|*[!a-zA-Z0-9._-]*) echo "invalid --name: $NAME" >&2; exit 1 ;;
esac

[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }

# --- arch ---
m=$(uname -m)
case "$m" in
    x86_64|amd64)   SUFFIX=linux-amd64 ;;
    aarch64|arm64)  SUFFIX=linux-arm64 ;;
    armv7*|armv8l)  SUFFIX=linux-armv7 ;;
    armv6*)         SUFFIX=linux-armv6 ;;
    riscv64)        SUFFIX=linux-riscv64 ;;
    mips*)
        endian=$(printf '\1\2' | od -An -tx2 | tr -d ' \n')
        case "$endian" in
            0201) SUFFIX=linux-mipsle-softfloat ;;
            0102) SUFFIX=linux-mips-softfloat ;;
            *) echo "cannot detect mips endianness ($endian)" >&2; exit 1 ;;
        esac
        ;;
    *) echo "unsupported arch: $m" >&2; exit 1 ;;
esac

# --- init system ---
if [ -f /etc/openwrt_release ] || [ -x /sbin/procd ]; then
    INIT=procd
elif [ -d /run/systemd/system ]; then
    INIT=systemd
elif command -v rc-update >/dev/null 2>&1; then
    INIT=openrc
else
    echo "unsupported init system" >&2
    exit 1
fi

# --- resolve tag ---
if [ -z "$TAG" ]; then
    TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n1)
    [ -n "$TAG" ] || { echo "could not resolve latest tag" >&2; exit 1; }
fi
TAG_ENC=$(echo "$TAG" | sed 's/+/%2B/g')
VER=${TAG%%+*}

ASSET="newt-${VER}-min-${SUFFIX}"
[ "$NO_UPX" -eq 0 ] && ASSET="${ASSET}.upx"
URL="https://github.com/${REPO}/releases/download/${TAG_ENC}/${ASSET}"

echo "arch:    $m -> $SUFFIX"
echo "init:    $INIT"
echo "tag:     $TAG"
echo "asset:   $ASSET"
echo

# --- download ---
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
echo "downloading $URL"
curl -fL --progress-bar -o "$tmp" "$URL"
chmod 0755 "$tmp"
mkdir -p "$(dirname "$BIN")"
mv "$tmp" "$BIN"

# --- env file ---
mkdir -p "$ETC_DIR"
ENV_FILE="${ETC_DIR}/${NAME}.env"

prompt_creds() {
    [ -r /dev/tty ] || { echo "no tty; cannot prompt. pre-create $ENV_FILE." >&2; exit 1; }
    printf '\npaste the newt run command (e.g. "newt --id X --secret Y --endpoint https://...")\n> ' > /dev/tty
    IFS= read -r CMD < /dev/tty

    ID=$(printf '%s\n' "$CMD"     | sed -n 's/.*--id[ =]*"\{0,1\}\([^" ]*\).*/\1/p')
    SECRET=$(printf '%s\n' "$CMD" | sed -n 's/.*--secret[ =]*"\{0,1\}\([^" ]*\).*/\1/p')
    ENDPOINT=$(printf '%s\n' "$CMD" | sed -n 's/.*--endpoint[ =]*"\{0,1\}\([^" ]*\).*/\1/p')

    if [ -z "$ID" ] || [ -z "$SECRET" ] || [ -z "$ENDPOINT" ]; then
        echo "could not parse --id/--secret/--endpoint from input" >&2
        exit 1
    fi

    umask 077
    cat > "$ENV_FILE" <<EOF
NEWT_ID=$ID
NEWT_SECRET=$SECRET
PANGOLIN_ENDPOINT=$ENDPOINT
EOF
    chmod 0600 "$ENV_FILE"
    echo "wrote $ENV_FILE"
}

if [ -f "$ENV_FILE" ] && [ "$UPDATE" -eq 0 ]; then
    echo "keeping existing $ENV_FILE (pass --update to replace)"
else
    prompt_creds
fi

# --- service ---
case "$INIT" in
    procd)
        SVC="/etc/init.d/${NAME}"
        cat > "$SVC" <<EOF
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10

start_service() {
    [ -r "$ENV_FILE" ] || return 1
    . "$ENV_FILE"
    procd_open_instance
    procd_set_param command $BIN
    procd_set_param env NEWT_ID="\$NEWT_ID" NEWT_SECRET="\$NEWT_SECRET" PANGOLIN_ENDPOINT="\$PANGOLIN_ENDPOINT"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
        chmod +x "$SVC"
        "$SVC" enable
        "$SVC" restart
        echo
        echo "service: $SVC"
        echo "logs:    logread -e $NAME -f"
        ;;
    systemd)
        SVC="/etc/systemd/system/${NAME}.service"
        cat > "$SVC" <<EOF
[Unit]
Description=newt tunnel ($NAME)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=$ENV_FILE
ExecStart=$BIN
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable "$NAME.service" >/dev/null
        systemctl restart "$NAME.service"
        echo
        echo "service: $SVC"
        echo "logs:    journalctl -u $NAME -f"
        ;;
    openrc)
        SVC="/etc/init.d/${NAME}"
        cat > "$SVC" <<EOF
#!/sbin/openrc-run
command="$BIN"
command_background=true
pidfile="/run/\$RC_SVCNAME.pid"
output_log="/var/log/\$RC_SVCNAME.log"
error_log="/var/log/\$RC_SVCNAME.log"

start_pre() {
    [ -r "$ENV_FILE" ] || return 1
    set -a
    . "$ENV_FILE"
    set +a
}

depend() {
    need net
}
EOF
        chmod +x "$SVC"
        rc-update add "$NAME" default >/dev/null
        rc-service "$NAME" restart
        echo
        echo "service: $SVC"
        echo "logs:    tail -f /var/log/$NAME.log"
        ;;
esac

echo "done."
