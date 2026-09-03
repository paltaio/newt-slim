# newt-slim

Stripped + UPX-compressed builds of [`fosrl/newt`](https://github.com/fosrl/newt)
for constrained Linux targets. Patches only - no upstream source is vendored.

## Quick install (router or Linux host)

Run once:

```sh
curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh | sh
```

It detects the arch and init system (procd, systemd, openrc), downloads the
matching binary, then prompts you to paste the `newt --id ... --secret ...
--endpoint ...` line and registers a service. When run without root, it asks
before installing a user service. If Docker is available, it can install a
container instead.

For options, download the installer:

```sh
curl -fsSLO https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh
chmod +x install.sh
```

Run multiple instances with `--name`:

```sh
./install.sh --name newt-home-router
```

Re-prompt for credentials with `--update`. Pin a release with `--tag 1.12.5`.
Use `--no-upx` if the UPX binary fails to run.

Credentials live in `/etc/newt/<name>.env` (mode 0600). The service unit is
`/etc/init.d/<name>` on procd/openrc or `/etc/systemd/system/<name>.service`
on systemd.

Install as a Docker container with `--docker`:

```sh
./install.sh --docker
```

The Docker installer creates a compose file when `docker compose` is available
and uses a `newt` Docker network. Rootless installs store credentials in
`${XDG_CONFIG_HOME:-$HOME/.config}/newt/<name>.env` unless `NEWT_CONFIG_DIR` is
set.

Stop or uninstall the native service:

```sh
./install.sh --stop

./install.sh --uninstall
```

Stop or uninstall the Docker container:

```sh
./install.sh --docker --stop

./install.sh --docker --uninstall
```

Add `--name <name>` to target a named instance.

## Android

Works in four setups, each starting newt at boot. Anything else fails.

| setup | what gets installed |
|---|---|
| Termux, with or without root | `~/.termux/boot/<name>.sh`, run by the Termux:Boot app |
| Magisk, KernelSU, APatch | a module at `/data/adb/modules/<name>` |
| `adb root` on a userdebug build | `/system/etc/init/<name>.rc`, started at `post-fs-data` |

Run the installer from the shell you have, `adb shell` plus `su` or a Termux
session:

```sh
curl -fsSL https://raw.githubusercontent.com/paltaio/newt-slim/main/install.sh | sh
```

Termux needs the Termux:Boot app installed and opened once. The boot script
takes a wake lock and logs to `~/.config/newt/<name>.log`.

The `adb root` path remounts `/system` writable. When verity was still
enabled, the remount asks for a reboot; reboot and run the installer again.
The service is picked up on the next reboot.

The module and `adb root` paths log to logcat:

```sh
adb logcat -s newt
```

Android has no `/etc/resolv.conf`, so newt sends DNS queries to its `--dns`
server, 9.9.9.9 by default.

`--stop`, `--uninstall`, and `--update` work the same way.

## Manual install

See [`docs/openwrt-manual-install.md`](docs/openwrt-manual-install.md).

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
