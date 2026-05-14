# syntax=docker/dockerfile:1.7

# Pull the system CA bundle from an Alpine stage. The runtime image is
# `scratch`, so this is the only thing we copy out.
FROM --platform=$BUILDPLATFORM public.ecr.aws/docker/library/alpine:3.23 AS certs
RUN apk --no-cache add ca-certificates

FROM scratch
ARG TARGETPLATFORM
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY bin/${TARGETPLATFORM}/newt /newt
ENTRYPOINT ["/newt"]
