# OpenWrt manual install

Manual procedure for OpenWrt routers such as GL.iNet and Teltonika RutOS.

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

Download and install. Set `TAG` and `SUFFIX` first:

```sh
TAG=1.12.5
SUFFIX=linux-armv7
wget -O /usr/bin/newt \
  "https://github.com/paltaio/newt-slim/releases/download/${TAG}%2Bmin/newt-${TAG}-min-${SUFFIX}.upx"
chmod +x /usr/bin/newt
```

Create `/etc/init.d/newt`:

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
