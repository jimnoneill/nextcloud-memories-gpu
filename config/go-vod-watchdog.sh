#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${HOME}/go-vod/docker-compose.yml"
CONTAINER_NAME="go-vod"
LOG_FILE="/var/log/go-vod-watchdog.log"
COOLDOWN_FILE="/tmp/go-vod-watchdog.last_restart"
COOLDOWN_SECONDS=600

log() {
    local level="$1"
    shift
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"
}

is_cooldown_active() {
    if [[ ! -f "$COOLDOWN_FILE" ]]; then
        return 1
    fi
    local last_restart now elapsed
    last_restart=$(cat "$COOLDOWN_FILE")
    now=$(date +%s)
    elapsed=$(( now - last_restart ))
    if (( elapsed < COOLDOWN_SECONDS )); then
        log "INFO" "Cooldown active: ${elapsed}s of ${COOLDOWN_SECONDS}s"
        return 0
    fi
    return 1
}

record_restart() {
    date +%s > "$COOLDOWN_FILE"
}

restart_container() {
    local reason="$1"
    if is_cooldown_active; then
        return 0
    fi
    log "WARN" "Restarting container: ${reason}"
    if docker restart "$CONTAINER_NAME" >> "$LOG_FILE" 2>&1; then
        log "INFO" "Container restarted successfully"
        record_restart
    else
        log "ERROR" "Container restart failed"
    fi
}

if ! docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -q '^true$'; then
    log "WARN" "Container ${CONTAINER_NAME} is not running; starting via docker compose"
    if is_cooldown_active; then
        exit 0
    fi
    if docker compose -f "$COMPOSE_FILE" up -d >> "$LOG_FILE" 2>&1; then
        log "INFO" "Container started successfully"
        record_restart
    else
        log "ERROR" "Failed to start container via docker compose"
    fi
    exit 0
fi

if ! docker exec "$CONTAINER_NAME" nvidia-smi > /dev/null 2>&1; then
    log "WARN" "nvidia-smi failed inside container"
    restart_container "nvidia-smi check failed"
    exit 0
fi

# Only scan logs since the container last started (avoids re-triggering on old errors)
started_at=$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null || echo "")
if [[ -n "$started_at" ]]; then
    recent_logs=$(docker logs --since "$started_at" "$CONTAINER_NAME" 2>&1 || true)
else
    recent_logs=$(docker logs --tail 100 "$CONTAINER_NAME" 2>&1 || true)
fi

if printf '%s' "$recent_logs" | grep -qE 'CUDA_ERROR_UNKNOWN|Device creation failed'; then
    log "WARN" "CUDA error signature found in container logs"
    restart_container "CUDA error detected in logs"
    exit 0
fi
