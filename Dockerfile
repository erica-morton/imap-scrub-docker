FROM ubuntu:24.04

WORKDIR /app
RUN DEBIAN_FRONTEND=noninteractive apt -y update && \
    DEBIAN_FRONTEND=noninteractive apt -y install curl && \
    curl -L -O https://github.com/axllent/imap-scrub/releases/latest/download/imap-scrub-linux-amd64.tar.gz && \
    curl -L -O https://github.com/axllent/imap-scrub/releases/latest/download/imap-scrub-linux-arm64.tar.gz && \
    if [ "$(uname -m)" = "x86_64" ]; then \
        tar -xzf imap-scrub-linux-amd64.tar.gz; \
    else \
        tar -xzf imap-scrub-linux-arm64.tar.gz; \
    fi && \
    rm imap-scrub-linux-*.tar.gz && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT [ "/app/imap-scrub" ]
