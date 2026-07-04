#!/bin/sh
set -e
tailscaled --state=/var/lib/tailscale/tailscaled.state \
  --socket=/var/run/tailscale/tailscaled.sock \
  --tun=userspace-networking &

tailscale up --authkey="$(cat /run/secrets/ts_authkey)" \
  --hostname=ollama \
  --advertise-tags=tag:ollama \
  --accept-dns=true

socat TCP-LISTEN:11434,fork,reuseaddr TCP:ollama:11434 &

tailscale serve --bg --tcp 11434 tcp://localhost:11434
wait