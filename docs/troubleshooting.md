# Troubleshooting

## Quick Fixes

| Symptom | Solution |
|---------|----------|
| Video stops at 5 seconds | [Enable GOP workaround](#video-stops-after-5-seconds) |
| CUDA_ERROR_UNKNOWN in logs | [Driver/toolkit mismatch](#cuda_error_unknown--cuinit-failed) |
| nvidia-smi works but ffmpeg fails | [Driver/toolkit mismatch](#cuda_error_unknown--cuinit-failed) |
| "Previews disabled" | [Re-run nextcloud config](#previews-disabled-error) |
| 408 timeout | [Increase timeouts](#timeout-errors) |
| No GPU activity | [Check NVIDIA toolkit](#no-gpu-utilization) |
| "No such file" | [Fix NFS mount](#nfs-path-issues) |

---

## Playback Issues

### Video Stops After 5 Seconds

**Cause**: NVENC keyframe placement incompatible with HLS streaming.

**Fix**:
1. Open **Admin Settings** -> **Memories** -> **Video Streaming**
2. Scroll to **HW Acceleration**
3. Enable **"GOP size workaround"**

This is the most common issue and must be enabled for NVENC.

### "Previews Disabled" Error

**Cause**: Memories can't validate go-vod configuration.

**Fix**:
```bash
docker exec nextcloud occ config:system:set memories.vod.path \
  --value="/config/www/nextcloud/apps/memories/bin-ext/go-vod-amd64"
docker exec nextcloud occ maintenance:repair
docker restart nextcloud
```

---

## Connection Issues

### go-vod Not Receiving Requests

**Test connectivity**:
```bash
# From Nextcloud container
docker exec nextcloud curl -s http://GPU_IP:47788/
# Expected: "Invalid URL /" (this is correct)
```

**Check firewall**:
```bash
ssh gpu-server 'sudo ufw allow 47788/tcp'
```

### Double http:// in Logs

**Cause**: You included `http://` in the connection address.

**Fix**: Use only `IP:PORT`:
```bash
docker exec nextcloud occ config:system:set memories.vod.connect \
  --value="192.168.1.20:47788"
```

---

## Timeout Errors

### 408 Request Timeout

First segment can take 5+ seconds to generate.

**Increase Caddy timeout**:
```
reverse_proxy backend {
    transport http {
        read_timeout 300s
        write_timeout 300s
    }
}
```

**Increase PHP timeout** (done automatically by deploy script):
```bash
docker exec nextcloud bash -c 'cat > /config/php/php-local.ini << EOF
max_execution_time = 300
max_input_time = 300
default_socket_timeout = 300
EOF'
```

---

## GPU Issues

### CUDA_ERROR_UNKNOWN / cuInit() Failed

**Symptom**: go-vod logs show:
```
cu->cuInit(0) failed -> CUDA_ERROR_UNKNOWN: unknown error
Device creation failed: -542398533.
No device available for decoder: device type cuda needed for codec h264
```

But `docker exec go-vod nvidia-smi` works fine.

**Cause**: The NVIDIA driver version is newer than what nvidia-container-toolkit
knows how to handle. Specifically, toolkit 1.19.0 does not pass
`/dev/nvidia-uvm-tools` into unprivileged containers when paired with driver
580.x+. nvidia-smi uses the management API (works without UVM), but CUDA's
`cuInit()` requires full UVM device access.

**Diagnose**:
```bash
./deploy.sh check-cuda
```

This runs an automated check comparing driver version, toolkit version, and
performs a live cuInit() test inside the container.

**Quick fix** (add `privileged: true` to docker-compose.yml):
```yaml
services:
  go-vod:
    privileged: true   # <-- add this line
    runtime: nvidia
    # ... rest of config
```
Then: `docker compose up -d`

The reference docker-compose.yml shipped with this repo already includes this flag.

**Proper fix** (update the toolkit):
```bash
sudo apt update && sudo apt install nvidia-container-toolkit
sudo systemctl restart docker
docker restart go-vod
```

After updating, you can remove `privileged: true` and verify with
`./deploy.sh check-cuda`.

**Watchdog**: The included `go-vod-watchdog.sh` (cron every 5 minutes) detects
CUDA failures via nvidia-smi and log scanning and auto-restarts the container.
However, if the underlying cause is a driver/toolkit mismatch, the restart alone
will not help -- you need the privileged flag or a toolkit update.

### No GPU Utilization

**Check NVIDIA Container Toolkit**:
```bash
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi
```

**If fails, install toolkit**:
```bash
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

### NVENC:false in Logs

go-vod couldn't detect GPU. Check:

```bash
# Verify GPU visible in container
docker exec go-vod nvidia-smi

# Check container runtime
docker inspect go-vod | grep -i runtime
```

---

## NFS Path Issues

### "No such file or directory"

go-vod sees paths like `/data/user/files/video.mp4`. The volume mapping must translate this correctly.

**Verify mount**:
```bash
# On GPU server
ls /mnt/nextcloud-data/
```

**Check docker-compose.yml**:
```yaml
volumes:
  - /mnt/nextcloud-data:/data:ro
```

### Mount Lost After Reboot

Add to `/etc/fstab`:
```
STORAGE_IP:/path/to/data /mnt/nextcloud-data nfs ro,_netdev 0 0
```

---

## Diagnostic Commands

```bash
# Full CUDA compatibility check
./deploy.sh check-cuda

# View all Memories settings
docker exec nextcloud occ config:list | grep -E "vod|transcode"

# go-vod logs
ssh gpu-server 'docker logs -f go-vod'

# Real-time GPU monitoring
ssh gpu-server 'watch -n1 nvidia-smi'

# Test transcoding
ssh gpu-server 'docker exec go-vod ffmpeg -hwaccel cuda \
  -i /data/USER/files/test.mp4 -c:v h264_nvenc -f null -'
```
