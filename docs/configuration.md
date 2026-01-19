# Configuration Reference

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `STORAGE_IP` | Yes | — | Storage server IP address |
| `GPU_IP` | Yes | — | GPU server IP address |
| `NEXTCLOUD_DATA` | Yes | — | Nextcloud data directory path |
| `DOMAIN` | Yes | — | Nextcloud domain name |
| `GO_VOD_PORT` | No | `47788` | go-vod listening port |
| `NEXTCLOUD_CONTAINER` | No | `nextcloud` | Docker container name |
| `NFS_MOUNT` | No | `/mnt/nextcloud-data` | NFS mount point on GPU server |
| `QUALITY` | No | `28` | Transcode quality (15-45) |
| `TIMEOUT` | No | `300` | Request timeout seconds |

---

## Nextcloud Settings

### System Level

Set via `occ config:system:set`:

| Key | Type | Description |
|-----|------|-------------|
| `memories.vod.external` | boolean | Use external transcoder |
| `memories.vod.connect` | string | GPU server `IP:PORT` |
| `memories.vod.path` | string | go-vod binary path |
| `memories.vod.nvenc` | boolean | Enable NVENC |
| `memories.vod.vaapi` | boolean | Enable VA-API |
| `memories.vod.qf` | integer | Quality factor |

### App Level

Set via `occ config:app:set memories`:

| Key | Description |
|-----|-------------|
| `vod.external` | External transcoder flag |
| `transcoder` | GPU server address |
| `vod.nvenc` | NVENC flag |
| `vod.use_gop_size` | GOP workaround flag |

---

## go-vod Container

```yaml
services:
  go-vod:
    image: radialapps/go-vod:latest
    container_name: go-vod
    restart: unless-stopped
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NEXTCLOUD_HOST=https://domain
    volumes:
      - /nfs/mount:/data:ro
      - ./tmp:/tmp/go-vod
    network_mode: host
```

### Startup Log Values

```
NVENC: true              # GPU encoding enabled
NVENCScale: cuda         # GPU scaling
Configured: true         # Successfully configured
StreamIdleTime: 60       # Seconds before cleanup
```

---

## NFS

### Server Export

```
/path/to/data CLIENT_IP(ro,sync,no_subtree_check,no_root_squash)
```

### Client Mount

```
SERVER:/path /mount/point nfs ro,_netdev 0 0
```

---

## Timeouts

All components need extended timeouts for transcoding:

| Component | Setting | Value |
|-----------|---------|-------|
| Caddy | `read_timeout`, `write_timeout` | 300s |
| Nginx | `fastcgi_read_timeout`, `fastcgi_send_timeout` | 300s |
| PHP | `max_execution_time`, `max_input_time` | 300 |

---

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 47788 | TCP | go-vod API |
| 2049 | TCP/UDP | NFS |
| 111 | TCP/UDP | NFS portmapper |
