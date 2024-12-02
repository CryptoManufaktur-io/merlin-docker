# Overview

Docker Compose for Merlin node.

The `./merlind` script can be used as a quick-start:

`./merlind install` brings in docker-ce, if you don't have Docker installed already.

`cp default.env .env`

`nano .env` and adjust variables as needed, particularly `NETWORK` and `L1_RPC`

`./merlind up`

To update the software, run `./merlind update` and then `./merlind up`

You can share the RPC/WS ports locally by adding `:rpc-shared.yml` to `COMPOSE_FILE` inside `.env`.

If meant to be used with [central-proxy-docker](https://github.com/CryptoManufaktur-io/central-proxy-docker) for traefik
and Prometheus remote write; use `:ext-network.yml` in `COMPOSE_FILE` inside `.env` in that case.

This is Merlin Docker v1.0.0
