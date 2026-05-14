# newt-slim

Stripped + UPX-compressed builds of [`fosrl/newt`](https://github.com/fosrl/newt)
for constrained Linux targets. Patches only - no upstream source is vendored.

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

## Install on an OpenWrt router (GL.iNet, Teltonika RutOS, etc.)

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
