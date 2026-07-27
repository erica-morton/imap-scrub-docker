FROM debian:bookworm-slim

ARG IMAP_SCRUB_VERSION=0.0.6
ARG TARGETARCH

WORKDIR /app
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    curl -fsSL -o imap-scrub.tar.gz \
        "https://github.com/axllent/imap-scrub/releases/download/${IMAP_SCRUB_VERSION}/imap-scrub-linux-${TARGETARCH}.tar.gz" && \
    tar -xzf imap-scrub.tar.gz && \
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
