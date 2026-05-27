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
