#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Nextcloud Memories GPU Transcoding - Deploy Script
# =============================================================================

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Colors & Formatting
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    DIM='\033[2m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' DIM='' BOLD='' NC=''
fi

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
info()    { echo -e "${BLUE}▸${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warn()    { echo -e "${YELLOW}!${NC} $1"; }
error()   { echo -e "${RED}✗${NC} $1" >&2; }
die()     { error "$1"; exit 1; }
step()    { echo -e "\n${BOLD}$1${NC}"; }

# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------
load_env() {
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        die "Missing .env file. Run: cp .env.example .env && nano .env"
    fi
    
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
    
    # Defaults
    : "${GO_VOD_PORT:=47788}"
    : "${NEXTCLOUD_CONTAINER:=nextcloud}"
    : "${NFS_MOUNT:=/mnt/nextcloud-data}"
    : "${QUALITY:=28}"
    : "${TIMEOUT:=300}"
}

validate_env() {
    local missing=()
    [[ -z "${STORAGE_IP:-}" ]] && missing+=("STORAGE_IP")
    [[ -z "${GPU_IP:-}" ]] && missing+=("GPU_IP")
    [[ -z "${NEXTCLOUD_DATA:-}" ]] && missing+=("NEXTCLOUD_DATA")
    [[ -z "${DOMAIN:-}" ]] && missing+=("DOMAIN")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required variables in .env: ${missing[*]}"
    fi
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
require_root() {
    [[ $EUID -eq 0 ]] || die "This command requires root. Run with sudo."
}

require_cmd() {
    command -v "$1" &>/dev/null || die "Required command not found: $1"
}

confirm() {
    read -rp "$(echo -e "${YELLOW}?${NC} $1 [y/N] ")" response
    [[ "$response" =~ ^[Yy]$ ]]
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------

cmd_storage() {
    require_root
    load_env
    validate_env
    
    step "Configuring NFS on storage server"
    
    info "Installing nfs-kernel-server..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nfs-kernel-server >/dev/null
    
    local export_line="${NEXTCLOUD_DATA} ${GPU_IP}(ro,sync,no_subtree_check,no_root_squash)"
    
    if grep -qF "${NEXTCLOUD_DATA}" /etc/exports 2>/dev/null; then
        warn "Export already exists in /etc/exports"
    else
        {
            echo ""
            echo "# Nextcloud Memories GPU Transcoding"
            echo "$export_line"
        } >> /etc/exports
        success "Added NFS export"
    fi
    
    exportfs -ra
    systemctl enable --now nfs-kernel-server >/dev/null 2>&1
    
    success "NFS configured"
    echo ""
    info "Export: ${DIM}${export_line}${NC}"
    echo ""
    echo -e "Next: Run ${BOLD}./deploy.sh gpu${NC} on the GPU server"
}

cmd_gpu() {
    load_env
    validate_env
    
    step "Setting up go-vod on GPU server"
    
    # Verify NVIDIA
    info "Checking NVIDIA GPU..."
    if ! command -v nvidia-smi &>/dev/null; then
        die "nvidia-smi not found. Install NVIDIA drivers first."
    fi
    local gpu_name
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    success "Found: $gpu_name"
    
    # Verify Docker
    info "Checking Docker..."
    require_cmd docker
    if ! docker info 2>/dev/null | grep -qi nvidia; then
        warn "NVIDIA Container Toolkit may not be installed"
        echo -e "  Install: ${DIM}https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html${NC}"
    fi
    success "Docker OK"
    
    # NFS mount
    step "Mounting NFS share"
    
    info "Installing nfs-common..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nfs-common >/dev/null
    fi
    
    sudo mkdir -p "$NFS_MOUNT"
    
    if mountpoint -q "$NFS_MOUNT" 2>/dev/null; then
        success "Already mounted"
    else
        info "Mounting ${STORAGE_IP}:${NEXTCLOUD_DATA}..."
        sudo mount -t nfs "${STORAGE_IP}:${NEXTCLOUD_DATA}" "$NFS_MOUNT" || \
            die "Mount failed. Check NFS server configuration."
        success "Mounted"
    fi
    
    # Persist mount
    local fstab_line="${STORAGE_IP}:${NEXTCLOUD_DATA} ${NFS_MOUNT} nfs ro,_netdev 0 0"
    if ! grep -qF "${STORAGE_IP}:${NEXTCLOUD_DATA}" /etc/fstab 2>/dev/null; then
        echo "$fstab_line" | sudo tee -a /etc/fstab >/dev/null
        success "Added to /etc/fstab"
    fi
    
    # Deploy go-vod
    step "Deploying go-vod"
    
    local govod_dir="$HOME/go-vod"
    mkdir -p "$govod_dir/tmp"
    chmod 777 "$govod_dir/tmp"
    
    cat > "$govod_dir/docker-compose.yml" << EOF
services:
  go-vod:
    image: radialapps/go-vod:latest
    container_name: go-vod
    restart: unless-stopped
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NEXTCLOUD_HOST=https://${DOMAIN}
    volumes:
      - ${NFS_MOUNT}:/data:ro
      - ./tmp:/tmp/go-vod
    network_mode: host
EOF
    
    success "Created docker-compose.yml"
    
    info "Starting container..."
    cd "$govod_dir"
    sudo docker compose pull -q
    sudo docker compose up -d
    sleep 3
    
    # Verify
    if sudo docker logs go-vod 2>&1 | grep -q "NVENC:true"; then
        success "go-vod running with NVENC"
    else
        warn "go-vod started but NVENC status unclear"
        echo -e "  Check: ${DIM}docker logs go-vod${NC}"
    fi
    
    echo ""
    echo -e "Next: Run ${BOLD}./deploy.sh nextcloud${NC} on the storage server"
}

cmd_nextcloud() {
    load_env
    validate_env
    
    step "Configuring Nextcloud Memories"
    
    local occ="docker exec ${NEXTCLOUD_CONTAINER} occ"
    
    # Verify container
    if ! docker ps --format '{{.Names}}' | grep -q "^${NEXTCLOUD_CONTAINER}$"; then
        die "Container '${NEXTCLOUD_CONTAINER}' not found"
    fi
    
    # Test connectivity
    info "Testing connection to go-vod..."
    if docker exec "$NEXTCLOUD_CONTAINER" curl -sf "http://${GPU_IP}:${GO_VOD_PORT}/" &>/dev/null || \
       docker exec "$NEXTCLOUD_CONTAINER" curl -s "http://${GPU_IP}:${GO_VOD_PORT}/" 2>&1 | grep -q "400"; then
        success "GPU server reachable"
    else
        warn "Could not reach GPU server (continuing anyway)"
    fi
    
    info "Applying Memories settings..."
    
    # System settings
    $occ config:system:set memories.vod.external --value="true" --type=boolean >/dev/null
    $occ config:system:set memories.vod.connect --value="${GPU_IP}:${GO_VOD_PORT}" >/dev/null
    $occ config:system:set memories.vod.nvenc --value="true" --type=boolean >/dev/null
    $occ config:system:set memories.vod.vaapi --value="false" --type=boolean >/dev/null
    $occ config:system:set memories.vod.qf --value="${QUALITY}" --type=integer >/dev/null
    $occ config:system:set memories.vod.path \
        --value="/config/www/nextcloud/apps/memories/bin-ext/go-vod-amd64" >/dev/null
    
    # App settings
    $occ config:app:set memories vod.external --value="true" >/dev/null
    $occ config:app:set memories transcoder --value="${GPU_IP}:${GO_VOD_PORT}" >/dev/null
    $occ config:app:set memories vod.nvenc --value="true" >/dev/null
    $occ config:app:set memories vod.vaapi --value="false" >/dev/null
    
    success "Memories configured"
    
    # Timeouts
    info "Configuring timeouts..."
    docker exec "$NEXTCLOUD_CONTAINER" bash -c "mkdir -p /config/php && cat > /config/php/php-local.ini << EOF
max_execution_time = ${TIMEOUT}
max_input_time = ${TIMEOUT}
default_socket_timeout = ${TIMEOUT}
EOF" 2>/dev/null
    
    docker exec "$NEXTCLOUD_CONTAINER" sed -i \
        "s/fastcgi_pass 127.0.0.1:9000;/fastcgi_pass 127.0.0.1:9000;\n        fastcgi_read_timeout ${TIMEOUT}s;\n        fastcgi_send_timeout ${TIMEOUT}s;/g" \
        /config/nginx/site-confs/default.conf 2>/dev/null || true
    
    success "Timeouts set to ${TIMEOUT}s"
    
    info "Running maintenance repair..."
    $occ maintenance:repair 2>&1 | grep -qE "go-vod.*configured" && \
        success "go-vod validated" || warn "Check admin panel for go-vod status"
    
    info "Restarting Nextcloud..."
    docker restart "$NEXTCLOUD_CONTAINER" >/dev/null
    
    success "Configuration complete"
    
    echo ""
    echo -e "${YELLOW}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│${NC}  ${BOLD}IMPORTANT: Manual step required${NC}                          ${YELLOW}│${NC}"
    echo -e "${YELLOW}├────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│${NC}                                                            ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  1. Open ${BOLD}Admin Settings → Memories → Video Streaming${NC}      ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  2. Scroll to ${BOLD}HW Acceleration${NC}                             ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  3. Enable ${BOLD}\"GOP size workaround\"${NC}                         ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}                                                            ${YELLOW}│${NC}"
    echo -e "${YELLOW}│${NC}  Without this, videos will stop after 5 seconds!           ${YELLOW}│${NC}"
    echo -e "${YELLOW}└────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "Run ${BOLD}./deploy.sh status${NC} to verify installation"
}

cmd_status() {
    load_env
    validate_env
    
    echo ""
    echo -e "${BOLD}Nextcloud Memories GPU Transcoding - Status${NC}"
    echo ""
    
    local errors=0
    
    # Nextcloud config
    echo -e "${BOLD}Nextcloud Configuration${NC}"
    
    local occ="docker exec ${NEXTCLOUD_CONTAINER} occ"
    local val
    
    val=$($occ config:system:get memories.vod.external 2>/dev/null || echo "—")
    [[ "$val" == "true" ]] && echo -e "  ${GREEN}✓${NC} External transcoder: enabled" || { echo -e "  ${RED}✗${NC} External transcoder: $val"; ((errors++)); }
    
    val=$($occ config:system:get memories.vod.connect 2>/dev/null || echo "—")
    [[ "$val" == "${GPU_IP}:${GO_VOD_PORT}" ]] && echo -e "  ${GREEN}✓${NC} Connect: $val" || { echo -e "  ${RED}✗${NC} Connect: $val (expected ${GPU_IP}:${GO_VOD_PORT})"; ((errors++)); }
    
    val=$($occ config:system:get memories.vod.nvenc 2>/dev/null || echo "—")
    [[ "$val" == "true" ]] && echo -e "  ${GREEN}✓${NC} NVENC: enabled" || { echo -e "  ${RED}✗${NC} NVENC: $val"; ((errors++)); }
    
    echo ""
    
    # go-vod
    echo -e "${BOLD}go-vod Status${NC}"
    
    if timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 "$GPU_IP" "docker ps -q -f name=go-vod" &>/dev/null; then
        if ssh "$GPU_IP" "docker logs go-vod 2>&1" | grep -q "NVENC:true"; then
            echo -e "  ${GREEN}✓${NC} Running with NVENC"
        else
            echo -e "  ${YELLOW}?${NC} Running (NVENC status unclear)"
        fi
    else
        echo -e "  ${DIM}?${NC} Could not connect to GPU server via SSH"
        echo -e "    ${DIM}Check manually: ssh $GPU_IP 'docker logs go-vod'${NC}"
    fi
    
    echo ""
    
    # Summary
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}All checks passed${NC}"
    else
        echo -e "${YELLOW}$errors issue(s) found${NC}"
    fi
    
    echo ""
    echo -e "${DIM}Don't forget to enable 'GOP size workaround' in Nextcloud admin!${NC}"
}

cmd_logs() {
    load_env
    validate_env
    
    echo -e "${DIM}Connecting to go-vod logs on ${GPU_IP}...${NC}"
    echo -e "${DIM}Press Ctrl+C to exit${NC}"
    echo ""
    
    ssh "$GPU_IP" "docker logs -f go-vod" 2>/dev/null || \
        die "Could not connect. Try: ssh $GPU_IP 'docker logs -f go-vod'"
}

cmd_help() {
    cat << EOF

${BOLD}Nextcloud Memories GPU Transcoding${NC} v${VERSION}

${BOLD}Usage:${NC}
    ./deploy.sh <command>

${BOLD}Commands:${NC}
    ${BOLD}storage${NC}     Configure NFS exports on storage server (requires sudo)
    ${BOLD}gpu${NC}         Deploy go-vod container on GPU server
    ${BOLD}nextcloud${NC}   Configure Nextcloud Memories settings
    ${BOLD}status${NC}      Check installation status
    ${BOLD}logs${NC}        Tail go-vod logs from GPU server
    ${BOLD}help${NC}        Show this message

${BOLD}Workflow:${NC}
    1. Edit .env with your configuration
    2. Run ${DIM}./deploy.sh storage${NC} on storage server
    3. Run ${DIM}./deploy.sh gpu${NC} on GPU server
    4. Run ${DIM}./deploy.sh nextcloud${NC} on storage server
    5. Enable "GOP size workaround" in Nextcloud admin
    6. Run ${DIM}./deploy.sh status${NC} to verify

${BOLD}Documentation:${NC}
    https://github.com/user/nextcloud-memories-gpu-transcoding

EOF
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    case "${1:-help}" in
        storage)   cmd_storage ;;
        gpu)       cmd_gpu ;;
        nextcloud) cmd_nextcloud ;;
        status)    cmd_status ;;
        logs)      cmd_logs ;;
        help|--help|-h) cmd_help ;;
        *)
            error "Unknown command: $1"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
