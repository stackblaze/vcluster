ARG KINE_VERSION="v0.14.4"
FROM docker.io/rancher/kine:${KINE_VERSION} AS kine

# Build program
FROM docker.io/library/golang:1.25 AS builder

WORKDIR /vcluster-dev
ARG TARGETOS
ARG TARGETARCH
ARG BUILD_VERSION=dev
ARG TELEMETRY_PRIVATE_KEY=""
ARG HELM_VERSION="v3.16.3"

# Install kubectl for development
RUN curl --retry 3 --retry-delay 2 -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/${TARGETARCH}/kubectl && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl

# Copy pre-downloaded helm binary from build context (workaround for network issues)
COPY helm-binary /usr/local/bin/helm
RUN chmod +x /usr/local/bin/helm

# Install Delve for debugging
RUN if [ "${TARGETARCH}" = "amd64" ] || [ "${TARGETARCH}" = "arm64" ]; then go install github.com/go-delve/delve/cmd/dlv@latest; fi

# Install kine
COPY --from=kine /bin/kine /usr/local/bin/kine

# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum
COPY vendor/ vendor/

# Copy the go source
COPY cmd/vcluster cmd/vcluster
COPY cmd/vclusterctl cmd/vclusterctl
COPY pkg/ pkg/
COPY config/ config/

ENV GO111MODULE=on
ENV DEBUG=true

# create and set GOCACHE now, this should slightly speed up the first build inside of the container
# also create /.config folder for GOENV, as dlv needs to write there when starting debugging
RUN mkdir -p /.cache /.config
ENV GOCACHE=/.cache
ENV GOENV=/.config

# Set home to "/" in order to for kubectl to automatically pick up vcluster kube config
ENV HOME=/

# Build cmd
RUN --mount=type=cache,id=gomod,target=/go/pkg/mod \
	--mount=type=cache,id=gobuild,target=/.cache/go-build \
	CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} GO111MODULE=on go build -mod vendor -ldflags "-X github.com/loft-sh/vcluster/pkg/telemetry.SyncerVersion=$BUILD_VERSION -X github.com/loft-sh/vcluster/pkg/telemetry.telemetryPrivateKey=$TELEMETRY_PRIVATE_KEY" -o /vcluster cmd/vcluster/main.go

# RUN useradd -u 12345 nonroot
# USER nonroot

ENTRYPOINT ["go", "run", "-mod", "vendor", "cmd/vcluster/main.go", "start"]

# we use alpine for easier debugging
FROM docker.io/library/alpine:3.22

# install runtime dependencies
RUN apk add --no-cache ca-certificates zstd tzdata

# Set root path as working directory
WORKDIR /

COPY --from=kine /bin/kine /usr/local/bin/kine
COPY --from=builder /vcluster .
COPY --from=builder /usr/local/bin/helm /usr/local/bin/helm

# RUN useradd -u 12345 nonroot
# USER nonroot

ENTRYPOINT ["/vcluster", "start"]
