FROM golang:1.21-alpine

RUN apk update && apk add --no-cache postgresql15-client git gnupg wget
COPY entrypoint.sh /usr/local/bin/
COPY snapshot_restore.toml /tmp/snapshot_restore.toml
COPY script.sql /tmp/script.sql

ENTRYPOINT [ "entrypoint.sh" ]
