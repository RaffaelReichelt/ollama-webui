#!/usr/bin/env bash
#
# update_ollama_models.sh
#
# Aktualisiert Ollama-Modelle in einem laufenden Docker-Container.
# Unterstützt: alle Modelle, ausgewählte Modelle, Ausschlussliste,
# Dry-Run (nur prüfen, ob Updates verfügbar sind) und ein einfaches Log.
#
# Nutzung:
#   ./update_ollama_models.sh                    # alle Modelle aktualisieren
#   ./update_ollama_models.sh -m modelA -m modelB # nur bestimmte Modelle
#   ./update_ollama_models.sh -x jina-v5-text     # alle außer diesem Modell
#   ./update_ollama_models.sh -n                  # Dry-Run (nur Statusprüfung)
#   ./update_ollama_models.sh -c ollama-prod      # anderer Container-/Servicename
#
# -c akzeptiert einen Containernamen oder einen Swarm-Servicenamen
# (Default: ollama_ollama -> Container ollama_ollama.1.<task-id>).
#
# Env-Var Alternative statt -c:
#   OLLAMA_CONTAINER=ollama-prod ./update_ollama_models.sh

set -euo pipefail

CONTAINER="${OLLAMA_CONTAINER:-ollama_ollama}"
DRY_RUN=false
declare -a ONLY_MODELS=()
declare -a EXCLUDE_MODELS=()
LOG_FILE="./ollama_update_$(date +%Y%m%d_%H%M%S).log"

usage() {
    grep '^#' "$0" | sed -n '2,20p' | sed 's/^#//'
    exit 1
}

while getopts "c:m:x:nh" opt; do
    case "$opt" in
        c) CONTAINER="$OPTARG" ;;
        m) ONLY_MODELS+=("$OPTARG") ;;
        x) EXCLUDE_MODELS+=("$OPTARG") ;;
        n) DRY_RUN=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $*" | tee -a "$LOG_FILE"
}

# --- Vorprüfungen ---------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
    echo "Fehler: docker ist nicht installiert oder nicht im PATH." >&2
    exit 1
fi

# Container auflösen: exakter Name, sonst Swarm-Task "<service>.<slot>.<task-id>"
RESOLVED=$(docker ps --format '{{.Names}}' | grep -E -x -m1 "${CONTAINER}|${CONTAINER}\.[0-9]+\.[a-z0-9]+" || true)

if [ -z "$RESOLVED" ]; then
    echo "Fehler: Container oder Swarm-Service '$CONTAINER' läuft nicht (docker ps zeigt ihn nicht)." >&2
    echo "Verfügbare laufende Container:" >&2
    docker ps --format '  - {{.Names}}' >&2
    exit 1
fi
CONTAINER="$RESOLVED"

log "Starte Ollama-Modell-Update in Container '$CONTAINER' (Dry-Run: $DRY_RUN)"

# --- Modellliste ermitteln -------------------------------------------------

mapfile -t ALL_MODELS < <(docker exec "$CONTAINER" ollama list | tail -n +2 | awk '{print $1}')

if [ "${#ALL_MODELS[@]}" -eq 0 ]; then
    log "Keine Modelle im Container gefunden. Abbruch."
    exit 0
fi

if [ "${#ONLY_MODELS[@]}" -gt 0 ]; then
    TARGET_MODELS=("${ONLY_MODELS[@]}")
else
    TARGET_MODELS=("${ALL_MODELS[@]}")
fi

# Ausschlussliste anwenden
if [ "${#EXCLUDE_MODELS[@]}" -gt 0 ]; then
    FILTERED=()
    for m in "${TARGET_MODELS[@]}"; do
        skip=false
        for ex in "${EXCLUDE_MODELS[@]}"; do
            [ "$m" == "$ex" ] && skip=true && break
        done
        $skip || FILTERED+=("$m")
    done
    TARGET_MODELS=("${FILTERED[@]}")
fi

log "Zu prüfende Modelle: ${TARGET_MODELS[*]}"

# --- Update-Schleife --------------------------------------------------------

UPDATED=()
UNCHANGED=()
FAILED=()

for model in "${TARGET_MODELS[@]}"; do
    log "----- $model -----"

    if $DRY_RUN; then
        # Kein echter Pull; nur digest-basierte Prüfung via 'ollama show' o.ä. ist
        # in Ollama nicht direkt vorgesehen, daher informativer Hinweis:
        log "[Dry-Run] Würde 'ollama pull $model' ausführen (kein tatsächlicher Download)."
        continue
    fi

    OUTPUT=$(docker exec "$CONTAINER" ollama pull "$model" 2>&1) || {
        log "FEHLER beim Pull von '$model':"
        log "$OUTPUT"
        FAILED+=("$model")
        continue
    }

    log "$OUTPUT"

    if echo "$OUTPUT" | grep -qi "up to date\|already exists"; then
        UNCHANGED+=("$model")
        log "-> bereits aktuell"
    else
        UPDATED+=("$model")
        log "-> aktualisiert"
    fi
done

# --- Zusammenfassung ---------------------------------------------------------

log "===== Zusammenfassung ====="
log "Aktualisiert:   ${UPDATED[*]:-keine}"
log "Bereits aktuell: ${UNCHANGED[*]:-keine}"
log "Fehlgeschlagen:  ${FAILED[*]:-keine}"
log "Log gespeichert unter: $LOG_FILE"

if [ "${#FAILED[@]}" -gt 0 ]; then
    exit 1
fi