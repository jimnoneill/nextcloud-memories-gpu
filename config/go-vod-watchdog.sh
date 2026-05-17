#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${HOME}/go-vod/docker-compose.yml"
CONTAINER_NAME="go-vod"
LOG_FILE="/var/log/go-vod-watchdog.log"
COOLDOWN_FILE="/tmp/go-vod-watchdog.last_restart"
COOLDOWN_SECONDS=600
LOG_LINES_TO_CHECK=100

log() {
    local level="$1"
    shift
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"
}

is_cooldown_active() {
    if [[ ! -f "$COOLDOWN_FILE" ]]; then
        return 1
    fi
    local last_restart
    last_restart=$(cat "$COOLDOWN_FILE")
    local now
    now=$(date +%s)
    local elapsed=$(( now - last_restart ))
    if (( elapsed < COOLDOWN_SECONDS )); then
        log "INFO" "Cooldown active: ${elapsed}s elapsed of ${COOLDOWN_SECONDS}s required since last restart"
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
    log "WARN" "nvidia-smi failed inside container; CUDA may be broken"
    restart_container "nvidia-smi check failed"
    exit 0
fi

recent_logs=$(docker logs --tail "$LOG_LINES_TO_CHECK" "$CONTAINER_NAME" 2>&1 || true)
if printf '%s' "$recent_logs" | grep -qE 'CUDA_ERROR_UNKNOWN|Device creation failed'; then
    log "WARN" "CUDA error signature found in container logs"
    restart_container "CUDA error detected in logs"
    exit 0
fi
