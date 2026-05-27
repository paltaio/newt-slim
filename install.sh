#!/bin/sh
# newt-slim installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh | sh -s -- --name newt-palta
#   curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh | sh -s -- --name newt-palta --update
#   curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh | sh -s -- --docker
set -eu

REPO=paltaio/newt-slim
BIN=/usr/bin/newt
ETC_DIR=/etc/newt
IMAGE=ghcr.io/paltaio/newt-slim

NAME=newt
TAG=
UPDATE=0
NO_UPX=0
DOCKER=0
STOP=0
UNINSTALL=0
DOCKER_CMD=
DOCKER_COMPOSE=
USER_INSTALL=0

usage() {
    cat <<EOF
install.sh [--name NAME] [--tag TAG] [--update] [--no-upx] [--docker]
install.sh [--name NAME] [--docker] --stop
install.sh [--name NAME] [--docker] --uninstall

  --name NAME   Service/instance name (default: newt). Run multiple instances
                by using a unique name per Pangolin site.
  --tag TAG     Release tag (default: latest, e.g. 1.12.5).
  --update      Re-prompt for credentials and overwrite the env file.
  --no-upx      Use the uncompressed binary.
  --docker      Run newt as a Docker container.
  --stop        Stop the service or container and keep its credentials.
  --uninstall   Stop and remove the service or container and credentials.
  --remove      Alias for --uninstall.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --name)
            [ $# -ge 2 ] || { echo "--name requires a value" >&2; exit 2; }
            NAME="$2"; shift 2
            ;;
        --tag)
            [ $# -ge 2 ] || { echo "--tag requires a value" >&2; exit 2; }
            TAG="$2"; shift 2
            ;;
        --update) UPDATE=1; shift ;;
        --no-upx) NO_UPX=1; shift ;;
        --docker) DOCKER=1; shift ;;
        --stop) STOP=1; shift ;;
        --uninstall|--remove) UNINSTALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$NAME" in
    ''|*[!a-zA-Z0-9._-]*) echo "invalid --name: $NAME" >&2; exit 1 ;;
esac

[ "$STOP" -eq 0 ] || [ "$UNINSTALL" -eq 0 ] || {
    echo "choose only one of --stop or --uninstall" >&2
    exit 2
}

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

ask_yes() {
    [ -r /dev/tty ] || return 1
    printf '%s [y/N] ' "$1" > /dev/tty
    IFS= read -r ANSWER < /dev/tty
    case "$ANSWER" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

docker_available() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

detect_docker() {
    command -v docker >/dev/null 2>&1 || { echo "docker command not found" >&2; exit 1; }

    if docker_available; then
        DOCKER_CMD=docker
        return
    fi

    echo "docker is not reachable. Start Docker or try running the installer with sudo." >&2
    exit 1
}

set_user_native_paths() {
    [ -n "${HOME:-}" ] || { echo "HOME is required for user install" >&2; exit 1; }
    USER_INSTALL=1
    BIN="${HOME}/.local/bin/newt"
    if [ -n "${XDG_CONFIG_HOME:-}" ]; then
        ETC_DIR="${XDG_CONFIG_HOME}/newt"
        USER_SYSTEMD_DIR="${XDG_CONFIG_HOME}/systemd/user"
    else
        ETC_DIR="${HOME}/.config/newt"
        USER_SYSTEMD_DIR="${HOME}/.config/systemd/user"
    fi
    ENV_FILE="${ETC_DIR}/${NAME}.env"
}

set_docker_env_dir() {
    if [ -n "${NEWT_CONFIG_DIR:-}" ]; then
        ETC_DIR=$NEWT_CONFIG_DIR
    elif [ "$(id -u)" -eq 0 ]; then
        ETC_DIR=/etc/newt
    elif [ -n "${XDG_CONFIG_HOME:-}" ]; then
        ETC_DIR="${XDG_CONFIG_HOME}/newt"
    elif [ -n "${HOME:-}" ]; then
        ETC_DIR="${HOME}/.config/newt"
    else
        echo "cannot choose a config directory. Set NEWT_CONFIG_DIR." >&2
        exit 1
    fi
    ENV_FILE="${ETC_DIR}/${NAME}.env"
    COMPOSE_FILE="${ETC_DIR}/${NAME}.compose.yml"
}

docker_container_exists() {
    $DOCKER_CMD container inspect "$NAME" >/dev/null 2>&1
}

docker_stop() {
    if [ -n "$DOCKER_COMPOSE" ] && [ -f "$COMPOSE_FILE" ]; then
        $DOCKER_COMPOSE -f "$COMPOSE_FILE" stop
        return
    fi

    if docker_container_exists; then
        $DOCKER_CMD stop "$NAME" >/dev/null
        echo "stopped container: $NAME"
    else
        echo "container not found: $NAME"
    fi
}

docker_uninstall() {
    if [ -n "$DOCKER_COMPOSE" ] && [ -f "$COMPOSE_FILE" ]; then
        $DOCKER_COMPOSE -f "$COMPOSE_FILE" down
        rm -f "$COMPOSE_FILE"
    elif docker_container_exists; then
        $DOCKER_CMD rm -f "$NAME" >/dev/null
        echo "removed container: $NAME"
    else
        echo "container not found: $NAME"
    fi

    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        rmdir "$ETC_DIR" 2>/dev/null || true
        echo "removed credentials: $ENV_FILE"
    fi
}

docker_install() {
    [ "$NO_UPX" -eq 0 ] || { echo "--no-upx is not used with --docker" >&2; exit 2; }

    if [ -z "$TAG" ]; then
        IMAGE_TAG=latest
    else
        IMAGE_TAG=${TAG%%+*}
    fi
    DOCKER_IMAGE="${IMAGE}:${IMAGE_TAG}"

    mkdir -p "$ETC_DIR"
    if [ -f "$ENV_FILE" ] && [ "$UPDATE" -eq 0 ]; then
        echo "keeping existing $ENV_FILE (pass --update to replace)"
    else
        prompt_creds
    fi

    if [ -n "$DOCKER_COMPOSE" ]; then
        cat > "$COMPOSE_FILE" <<EOF
services:
  newt:
    image: $DOCKER_IMAGE
    container_name: $NAME
    restart: unless-stopped
    env_file:
      - $ENV_FILE
    networks:
      - newt

networks:
  newt:
    name: newt
EOF
        $DOCKER_COMPOSE -f "$COMPOSE_FILE" up -d || {
            echo "docker compose failed. Try running the installer with sudo if Docker requires it." >&2
            exit 1
        }
        echo
        echo "done."
        echo "actions:"
        echo "  container: $NAME"
        echo "  image: $DOCKER_IMAGE"
        echo "  credentials: $ENV_FILE"
        echo "  compose: $COMPOSE_FILE"
        echo "  network: newt"
        echo "  logs: docker compose -f $COMPOSE_FILE logs -f"
        return
    fi

    $DOCKER_CMD pull "$DOCKER_IMAGE" || {
        echo "docker pull failed. Try running the installer with sudo if Docker requires it." >&2
        exit 1
    }
    $DOCKER_CMD network inspect newt >/dev/null 2>&1 || $DOCKER_CMD network create newt >/dev/null || {
        echo "docker network create failed. Try running the installer with sudo if Docker requires it." >&2
        exit 1
    }
    if docker_container_exists; then
        $DOCKER_CMD rm -f "$NAME" >/dev/null
    fi
    $DOCKER_CMD run -d \
        --name "$NAME" \
        --restart unless-stopped \
        --network newt \
        --env-file "$ENV_FILE" \
        "$DOCKER_IMAGE" >/dev/null || {
            echo "docker run failed. Try running the installer with sudo if Docker requires it." >&2
            exit 1
        }

    echo
    echo "done."
    echo "actions:"
    echo "  container: $NAME"
    echo "  image: $DOCKER_IMAGE"
    echo "  credentials: $ENV_FILE"
    echo "  network: newt"
    echo "  logs: $DOCKER_CMD logs -f $NAME"
}

native_stop() {
    FOUND=0

    if [ "$USER_INSTALL" -eq 1 ]; then
        systemctl --user stop "$NAME.service" >/dev/null 2>&1 || true
        echo "stopped service: $NAME"
        return
    fi

    if [ -f "/etc/systemd/system/${NAME}.service" ] && command -v systemctl >/dev/null 2>&1; then
        systemctl stop "$NAME.service" >/dev/null 2>&1 || true
        FOUND=1
    fi

    if [ -x "/etc/init.d/${NAME}" ]; then
        if head -n1 "/etc/init.d/${NAME}" | grep -q openrc-run && command -v rc-service >/dev/null 2>&1; then
            rc-service "$NAME" stop >/dev/null 2>&1 || true
        else
            "/etc/init.d/${NAME}" stop >/dev/null 2>&1 || true
        fi
        FOUND=1
    fi

    if [ "$FOUND" -eq 1 ]; then
        echo "stopped service: $NAME"
    else
        echo "service not found: $NAME"
    fi
}

native_uninstall() {
    FOUND=0

    if [ "$USER_INSTALL" -eq 1 ]; then
        systemctl --user stop "$NAME.service" >/dev/null 2>&1 || true
        systemctl --user disable "$NAME.service" >/dev/null 2>&1 || true
        rm -f "${USER_SYSTEMD_DIR}/${NAME}.service" "$ENV_FILE"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        if [ -z "$(find "$ETC_DIR" -type f -name '*.env' 2>/dev/null | sed -n '1p')" ]; then
            rm -f "$BIN"
        fi
        rmdir "$ETC_DIR" 2>/dev/null || true
        echo "removed service: $NAME"
        return
    fi

    if [ -f "/etc/systemd/system/${NAME}.service" ] && command -v systemctl >/dev/null 2>&1; then
        systemctl stop "$NAME.service" >/dev/null 2>&1 || true
        systemctl disable "$NAME.service" >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/${NAME}.service"
        systemctl daemon-reload >/dev/null 2>&1 || true
        FOUND=1
    fi

    if [ -x "/etc/init.d/${NAME}" ]; then
        if head -n1 "/etc/init.d/${NAME}" | grep -q openrc-run && command -v rc-service >/dev/null 2>&1; then
            rc-service "$NAME" stop >/dev/null 2>&1 || true
            rc-update del "$NAME" default >/dev/null 2>&1 || true
        else
            "/etc/init.d/${NAME}" stop >/dev/null 2>&1 || true
            "/etc/init.d/${NAME}" disable >/dev/null 2>&1 || true
        fi
        rm -f "/etc/init.d/${NAME}"
        FOUND=1
    fi

    if [ "$FOUND" -eq 1 ]; then
        echo "removed service: $NAME"
    else
        echo "service not found: $NAME"
    fi

    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        echo "removed credentials: $ENV_FILE"
    fi

    if [ -z "$(find "$ETC_DIR" -type f -name '*.env' 2>/dev/null | sed -n '1p')" ]; then
        rm -f "$BIN"
        rmdir "$ETC_DIR" 2>/dev/null || true
        echo "removed binary: $BIN"
    fi
}

if [ "$DOCKER" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
    if [ "$STOP" -eq 1 ] || [ "$UNINSTALL" -eq 1 ]; then
        set_user_native_paths
    elif ask_yes "Install newt as a user service?"; then
        set_user_native_paths
    elif docker_available && ask_yes "Install newt with Docker?"; then
        DOCKER=1
    else
        echo "run as root or pass --docker" >&2
        exit 1
    fi
fi

if [ "$DOCKER" -eq 1 ]; then
    detect_docker
    set_docker_env_dir
    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    fi

    if [ "$STOP" -eq 1 ]; then
        docker_stop
        exit 0
    fi

    if [ "$UNINSTALL" -eq 1 ]; then
        docker_uninstall
        exit 0
    fi

    docker_install
    exit 0
fi

if [ "$USER_INSTALL" -eq 0 ]; then
    [ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }
    ENV_FILE="${ETC_DIR}/${NAME}.env"
fi

if [ "$STOP" -eq 1 ]; then
    native_stop
    exit 0
fi

if [ "$UNINSTALL" -eq 1 ]; then
    native_uninstall
    exit 0
fi

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
if [ "$USER_INSTALL" -eq 1 ]; then
    command -v systemctl >/dev/null 2>&1 || { echo "systemctl is required for user install" >&2; exit 1; }
    INIT=systemd-user
elif [ -f /etc/openwrt_release ] || [ -x /sbin/procd ]; then
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
case "$TAG" in
    *+*) ;;
    *) TAG="${TAG}+min" ;;
esac
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
        "$SVC" stop >/dev/null 2>&1 || true
        "$SVC" start
        LOGS_CMD="logread -e $NAME -f"
        ;;
    systemd-user)
        SVC="${USER_SYSTEMD_DIR}/${NAME}.service"
        mkdir -p "$USER_SYSTEMD_DIR"
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

[Install]
WantedBy=default.target
EOF
        systemctl --user daemon-reload
        systemctl --user enable "$NAME.service" >/dev/null
        systemctl --user restart "$NAME.service"
        LOGS_CMD="journalctl --user -u $NAME -f"
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
        LOGS_CMD="journalctl -u $NAME -f"
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
        LOGS_CMD="tail -f /var/log/$NAME.log"
        ;;
esac

echo
echo "done."
echo "actions:"
echo "  service: $SVC"
echo "  binary: $BIN"
echo "  credentials: $ENV_FILE"
echo "  logs: $LOGS_CMD"
