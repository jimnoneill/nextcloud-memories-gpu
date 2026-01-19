# Admin UI Configuration

Settings in the Nextcloud web interface.

## Location

**Admin Settings** → **Memories** → **Video Streaming**

---

## Required Settings

### Transcoder

| Setting | Value |
|---------|-------|
| Use external transcoder | ✓ |
| Connection address | `GPU_IP:47788` |

> ⚠️ No `http://` prefix — just `IP:PORT`

### HW Acceleration

| Setting | Value |
|---------|-------|
| Enable VA-API | ✗ |
| Enable NVENC | ✓ |
| **Enable GOP size workaround** | **✓** |

---

## Critical: GOP Size Workaround

This setting **must be enabled** for NVENC to work properly.

**Without it**: Videos play 5 seconds, then buffer forever.

**Location**: HW Acceleration → NVENC → Enable GOP size workaround

---

## Verification

After configuration, verify:

```
✓ go-vod binary exists and is usable (0.2.6)
```

If you see errors about binary path:

```bash
docker exec nextcloud occ config:system:set memories.vod.path \
  --value="/config/www/nextcloud/apps/memories/bin-ext/go-vod-amd64"
docker exec nextcloud occ maintenance:repair
docker restart nextcloud
```

---

## Settings via CLI

If the UI is problematic, set everything via command line:

```bash
occ config:system:set memories.vod.external --value="true" --type=boolean
occ config:system:set memories.vod.connect --value="192.168.1.20:47788"
occ config:system:set memories.vod.nvenc --value="true" --type=boolean
occ config:system:set memories.vod.vaapi --value="false" --type=boolean
occ config:app:set memories vod.use_gop_size --value="true"
```
