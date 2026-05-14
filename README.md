# newt-slim

Stripped + UPX-compressed builds of [`fosrl/newt`](https://github.com/fosrl/newt)
for constrained Linux targets. Patches only - no upstream source is vendored.

## Build

```bash
scripts/build.sh v1.12.2 linux arm 7
scripts/build.sh v1.12.2 linux mipsle softfloat
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

## What `-tags=minimal` removes

OpenTelemetry / Prometheus / gRPC, Docker SDK, GitHub update check,
auth-daemon. Stubs return errors or no-ops; the WireGuard data plane,
websocket control channel, gvisor netstack, and mTLS are untouched.
