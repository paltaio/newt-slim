# newt-slim

Stripped + UPX-compressed builds of [`fosrl/newt`](https://github.com/fosrl/newt)
for constrained Linux targets. Patches only - no upstream source is vendored.

## Quick install (router or Linux host)

Run:

```sh
curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh | sh
```

It detects the arch and init system (procd, systemd, openrc), downloads the
matching binary, then prompts you to paste the `newt --id ... --secret ...
--endpoint ...` line and registers a service. When run without root, it asks
before installing a user service. If Docker is available, it can install a
container instead.

Run multiple instances with `--name`:

```sh
curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh \
  | sh -s -- --name newt-home-router
```

Re-prompt for credentials with `--update`. Pin a release with `--tag 1.12.5`.
Use `--no-upx` if the UPX binary fails to run.

Credentials live in `/etc/newt/<name>.env` (mode 0600). The service unit is
`/etc/init.d/<name>` on procd/openrc or `/etc/systemd/system/<name>.service`
on systemd.

Install as a Docker container with `--docker`:

```sh
curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh \
  | sh -s -- --docker
```

The Docker installer creates a compose file when `docker compose` is available
and uses a `newt` Docker network. Rootless installs store credentials in
`${XDG_CONFIG_HOME:-$HOME/.config}/newt/<name>.env` unless `NEWT_CONFIG_DIR` is
set.

Stop or uninstall the native service:

```sh
curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh \
  | sh -s -- --stop

curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh \
  | sh -s -- --uninstall
```

Stop or uninstall the Docker container:

```sh
curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh \
  | sh -s -- --docker --stop

curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh \
  | sh -s -- --docker --uninstall
```

Add `--name <name>` to target a named instance.

## Install on an OpenWrt router (GL.iNet, Teltonika RutOS, etc.)

Manual procedure if you'd rather not run the installer.

SSH in and detect the arch:

```sh
ssh root@192.168.8.1
uname -m
opkg print-architecture | awk '{print $2}'
```

Pick the matching asset suffix:

| `uname -m` / opkg arch         | asset suffix             |
|--------------------------------|--------------------------|
| `mips` + `mips_*`              | `linux-mips-softfloat`   |
| `mips` + `mipsel_*`            | `linux-mipsle-softfloat` |
| `armv7l` / `arm_cortex-a*`     | `linux-armv7`            |
| `aarch64` / `aarch64_*`        | `linux-arm64`            |

Download and install (set `TAG` and `SUFFIX`):

```sh
TAG=1.12.5
SUFFIX=linux-armv7
wget -O /usr/bin/newt \
  "https://github.com/paltaio/newt-slim/releases/download/${TAG}%2Bmin/newt-${TAG}-min-${SUFFIX}.upx"
chmod +x /usr/bin/newt
```

Create `/etc/init.d/newt` (procd):

```sh
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10

NEWT_ID="your-newt-id"
NEWT_SECRET="your-newt-secret"
NEWT_ENDPOINT="https://pangolin.example.com"

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/newt \
        --id "$NEWT_ID" \
        --secret "$NEWT_SECRET" \
        --endpoint "$NEWT_ENDPOINT"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
```

Enable and start:

```sh
chmod +x /etc/init.d/newt
/etc/init.d/newt enable
/etc/init.d/newt start
logread -e newt -f
```

## What `-tags=minimal` removes

OpenTelemetry / Prometheus / gRPC, Docker SDK, GitHub update check,
auth-daemon. Stubs return errors or no-ops; the WireGuard data plane,
websocket control channel, gvisor netstack, and mTLS are untouched.

## Build

```bash
scripts/build.sh 1.12.5 linux arm 7
scripts/build.sh 1.12.5 linux mipsle softfloat
```

Outputs to `./out/`.

## Workflow

`.github/workflows/release.yml` runs daily. For each new upstream tag it
clones the source, applies `patches/*.patch`, cross-compiles every target in
the matrix, and publishes a `<tag>+min` release with stripped and `.upx`
artifacts plus `SHA256SUMS`.

If a patch fails to apply, the build fails. Refresh `patches/` against the
new upstream tag and push.

## Container image

```
docker pull ghcr.io/paltaio/newt-slim:latest
```

See [`compose.yml`](compose.yml).
