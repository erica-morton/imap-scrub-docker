FROM debian:bookworm-slim

ARG IMAP_SCRUB_VERSION=v0.3.0
# Release-tarball checksums, per architecture — update together with the version
ARG IMAP_SCRUB_SHA256_amd64=896eacdb3d2742d9d5f32d2cc163d1656e27963fabc1a8b5206a0aaa32a302e0
ARG IMAP_SCRUB_SHA256_arm64=419559658d22628ca057529cdcdc5a14f70cdfca27b33a2e5bb7beb6ebd425f4
ARG TARGETARCH

WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    curl -fsSL -o imap-scrub.tar.gz \
        "https://github.com/mixeme/imap-scrub/releases/download/${IMAP_SCRUB_VERSION}/imap-scrub-linux-${TARGETARCH}.tar.gz" && \
    eval "expected=\"\$IMAP_SCRUB_SHA256_${TARGETARCH}\"" && \
    echo "${expected}  imap-scrub.tar.gz" | sha256sum -c - && \
    tar -xzf imap-scrub.tar.gz imap-scrub && \
    rm imap-scrub.tar.gz && \
    apt-get purge -y curl && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh && \
    useradd --uid 10001 --create-home scrub && \
    mkdir -p /config /data && \
    chown scrub:scrub /config /data

USER scrub
# save_attachments writes to the current directory by default
WORKDIR /data

ENTRYPOINT ["/app/entrypoint.sh"]
