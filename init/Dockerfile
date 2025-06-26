FROM debian:bookworm-slim

COPY fetch-snapshot.sh /usr/local/bin/

RUN mkdir /tmp/cdk-erigon && chown -R 1000:1000 /tmp/cdk-erigon

RUN apt-get update && DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y ca-certificates tzdata aria2 curl zstd lz4 \
        && rm -rf /var/lib/apt/lists/*

ENTRYPOINT [ "fetch-snapshot.sh" ]
