# Manual Setup

Step-by-step installation without the automated scripts.

---

## 1. Storage Server: NFS

```bash
# Install
sudo apt update && sudo apt install -y nfs-kernel-server

# Configure (edit paths and IPs)
echo "/mnt/nextcloud/data 192.168.1.20(ro,sync,no_subtree_check,no_root_squash)" | \
  sudo tee -a /etc/exports

# Apply
sudo exportfs -ra
sudo systemctl enable --now nfs-kernel-server
```

---

## 2. GPU Server: Prerequisites

```bash
# Verify GPU
nvidia-smi

# Docker (if needed)
curl -fsSL https://get.docker.com | sh

# NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker

# Verify
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

---

## 3. GPU Server: NFS Mount

```bash
# Install client
sudo apt install -y nfs-common

# Create mount point
sudo mkdir -p /mnt/nextcloud-data

# Mount (edit IP and path)
sudo mount 192.168.1.10:/mnt/nextcloud/data /mnt/nextcloud-data

# Verify
ls /mnt/nextcloud-data

# Persist
echo "192.168.1.10:/mnt/nextcloud/data /mnt/nextcloud-data nfs ro,_netdev 0 0" | \
  sudo tee -a /etc/fstab
```

---

## 4. GPU Server: go-vod

```bash
mkdir -p ~/go-vod/tmp && chmod 777 ~/go-vod/tmp && cd ~/go-vod

cat > docker-compose.yml << 'EOF'
services:
  go-vod:
    image: radialapps/go-vod:latest
    container_name: go-vod
    restart: unless-stopped
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NEXTCLOUD_HOST=https://cloud.example.com
    volumes:
      - /mnt/nextcloud-data:/data:ro
      - ./tmp:/tmp/go-vod
    network_mode: host
EOF

sudo docker compose up -d

# Verify NVENC
sudo docker logs go-vod | grep NVENC
```

---

## 5. Storage Server: Nextcloud Config

```bash
CONTAINER=nextcloud
GPU=192.168.1.20
PORT=47788

# System settings
docker exec $CONTAINER occ config:system:set memories.vod.external --value="true" --type=boolean
docker exec $CONTAINER occ config:system:set memories.vod.connect --value="${GPU}:${PORT}"
docker exec $CONTAINER occ config:system:set memories.vod.nvenc --value="true" --type=boolean
docker exec $CONTAINER occ config:system:set memories.vod.vaapi --value="false" --type=boolean
docker exec $CONTAINER occ config:system:set memories.vod.path \
  --value="/config/www/nextcloud/apps/memories/bin-ext/go-vod-amd64"

# App settings
docker exec $CONTAINER occ config:app:set memories vod.external --value="true"
docker exec $CONTAINER occ config:app:set memories transcoder --value="${GPU}:${PORT}"
docker exec $CONTAINER occ config:app:set memories vod.nvenc --value="true"

# Repair and restart
docker exec $CONTAINER occ maintenance:repair
docker restart $CONTAINER
```

---

## 6. Storage Server: Timeouts

```bash
# PHP
docker exec nextcloud bash -c 'mkdir -p /config/php && cat > /config/php/php-local.ini << EOF
max_execution_time = 300
max_input_time = 300
default_socket_timeout = 300
EOF'

# Nginx
docker exec nextcloud sed -i \
  's/fastcgi_pass 127.0.0.1:9000;/fastcgi_pass 127.0.0.1:9000;\n        fastcgi_read_timeout 300s;\n        fastcgi_send_timeout 300s;/g' \
  /config/nginx/site-confs/default.conf

docker restart nextcloud
```

---

## 7. Admin UI

1. **Admin Settings** → **Memories** → **Video Streaming**
2. Verify: "go-vod binary exists and is usable"
3. Enable: **GOP size workaround** (critical!)

---

## 8. Verify

```bash
# Check config
docker exec nextcloud occ config:list | grep vod

# Watch transcoding
ssh gpu-server 'docker logs -f go-vod'

# Monitor GPU
ssh gpu-server 'nvidia-smi'
```
