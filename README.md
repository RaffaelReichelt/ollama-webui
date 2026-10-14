# Ollama-Stack (Docker Swarm)

Zwei Services im Stack `ollama`:

- `ollama` – Ollama, nur im Overlay-Netz `backend` erreichbar (keine veröffentlichten Ports).
- `ollama-tailscale` – Standard-Image `tailscale/tailscale` als Sidecar. Veröffentlicht Ollama im Tailnet
  als `https://ollama.<tailnet>.ts.net:11434` (Proxy auf `http://ollama:11434`, siehe `serve.json`).

## Pfade auf dem Host

| Pfad | Inhalt |
|---|---|
| `/var/lib/ollama` | Modelle, Cache, Ollama-Schlüssel (`/root/.ollama` im Container) |
| `/opt/ollama/serve.json` | Tailscale-Serve-Konfiguration (Vorlage: `serve.json` in diesem Repo) |

Beide Pfade lassen sich über `OLLAMA_DATA_DIR` und `OLLAMA_SERVE_JSON` überschreiben.

## Deployment

```bash
sudo mkdir -p /opt/ollama /var/lib/ollama
sudo cp serve.json /opt/ollama/serve.json
docker stack deploy -c docker-compose.yml ollama
```

Das Swarm-Secret `ts_authkey` muss existieren (siehe unten).

**Hinweis:** Dem Sidecar kein `hostname:` geben. Sonst löst `ollama` im Overlay auf den Sidecar selbst
auf statt auf den Ollama-Service, und der Proxy liefert 502. Der Tailnet-Name kommt aus `TS_HOSTNAME`.

## Tailscale-Auth-Key (`ts_authkey`)

Das Secret `ts_authkey` wird systemseitig rotiert (Skript im Projekt `key-rotation`,
`scripts/rotate-ts-authkey.sh`). Es wird dabei neu angelegt und der Sidecar zweimal neu gestartet.

- Der Auth-Key wird nur bei der Erstanmeldung gebraucht. Mit persistiertem `ts_state`-Volume
  meldet sich der Sidecar ohne ihn wieder an; ein abgelaufener Key stört dann nicht.
- Er ist deshalb nur relevant, wenn der State leer ist (neuer Host, gelöschtes Volume).
- Das Secret darf in der Compose nur als `external` mit dem Namen `ts_authkey` stehen. Die Rotation ersetzt
  Inhalt und Secret-ID, nicht den Namen.

## Modelle pflegen

`./update_ollama_models.sh` aktualisiert alle installierten Modelle (`-n` für Trockenlauf,
`-m` für einzelne Modelle, `-x` zum Ausschließen). Der Container wird automatisch gefunden,
auch als Swarm-Task `ollama_ollama.1.<id>`. Bereits entfernte Modelle werden nicht neu angelegt.

`bench/`-Ergebnisse (`bench_*.csv`) und Update-Logs (`*.log`) werden nicht versioniert.
`ollama_bench.py` erzeugt die Benchmarks.
