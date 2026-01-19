<p align="center">
  <img src="docs/assets/logo.svg" alt="Memories GPU Transcoding" width="120">
</p>

<h1 align="center">Nextcloud Memories GPU Transcoding</h1>

<p align="center">
  <strong>Offload video transcoding to a dedicated GPU server</strong>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#how-it-works">How It Works</a> •
  <a href="docs/troubleshooting.md">Troubleshooting</a> •
  <a href="docs/configuration.md">Configuration</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Nextcloud-Memories%207.0+-0082c9?style=flat-square&logo=nextcloud" alt="Nextcloud Memories">
  <img src="https://img.shields.io/badge/NVIDIA-NVENC-76b900?style=flat-square&logo=nvidia" alt="NVIDIA NVENC">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License">
</p>

---

## Why?

Nextcloud Memories transcodes videos on-the-fly for smooth browser playback. Without a GPU, this hammers your CPU. This project lets you offload transcoding to a separate machine with an NVIDIA GPU.

```
┌─────────────────────┐                    ┌─────────────────────┐
│   STORAGE SERVER    │                    │     GPU SERVER      │
│                     │      NFS (ro)      │                     │
│   Nextcloud         │◄──────────────────►│   RTX 3080/4090     │
│   Memories          │                    │   go-vod + NVENC    │
│   Your Files        │◄──────────────────►│   HLS Segments      │
│                     │    HTTP :47788     │                     │
└─────────────────────┘                    └─────────────────────┘
```

## Quick Start

### Prerequisites

| | Storage Server | GPU Server |
|-|----------------|------------|
| **OS** | Ubuntu 22.04+ | Ubuntu 22.04+ |
| **Docker** | ✓ | ✓ |
| **NFS** | server | client |
| **GPU** | — | NVIDIA GTX 1000+ |
| **Drivers** | — | 525.0+ |

### 1. Clone & Configure

```bash
git clone https://github.com/user/nextcloud-memories-gpu-transcoding
cd nextcloud-memories-gpu-transcoding
cp .env.example .env
```

Edit `.env` with your details:

```bash
STORAGE_IP=192.168.1.10       # Your Nextcloud server
GPU_IP=192.168.1.20           # Your GPU machine
NEXTCLOUD_DATA=/mnt/data      # Path to Nextcloud data
DOMAIN=cloud.example.com      # Your Nextcloud domain
```

### 2. Deploy

```bash
# On storage server
./deploy.sh storage

# On GPU server
./deploy.sh gpu

# On storage server again
./deploy.sh nextcloud
```

### 3. Enable GOP Workaround

> ⚠️ **Critical**: Without this, videos stop after 5 seconds.

1. **Admin Settings** → **Memories** → **Video Streaming**
2. Scroll to **HW Acceleration**
3. Enable **"GOP size workaround"**

### 4. Verify

```bash
./deploy.sh status
```

Play a video in Memories. Check GPU activity:

```bash
ssh gpu-server 'nvidia-smi'
```

---

## How It Works

1. User opens video in Memories
2. Nextcloud forwards request to go-vod on GPU server (`:47788`)
3. go-vod reads source file via NFS mount
4. NVENC hardware encodes to HLS segments
5. Segments stream back through Nextcloud to user

**Result**: Smooth 1080p/4K playback without CPU strain on your storage server.

---

## Commands

```bash
./deploy.sh storage    # Configure NFS exports
./deploy.sh gpu        # Deploy go-vod container
./deploy.sh nextcloud  # Configure Memories settings
./deploy.sh status     # Verify installation
./deploy.sh logs       # Tail go-vod logs
./deploy.sh help       # Show all commands
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Configuration](docs/configuration.md) | All settings reference |
| [Troubleshooting](docs/troubleshooting.md) | Common issues & fixes |
| [Manual Setup](docs/manual-setup.md) | Step-by-step without scripts |
| [Admin UI](docs/admin-ui.md) | Nextcloud admin settings |

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Video stops at 5s | Enable GOP workaround in admin |
| "Previews disabled" | Run `./deploy.sh nextcloud` |
| 408 timeout | Check proxy timeout settings |
| No GPU usage | Verify NVIDIA Container Toolkit |

[Full troubleshooting guide →](docs/troubleshooting.md)

---

## Requirements

- **Memories**: 7.0+
- **go-vod**: 0.2.6+
- **NVIDIA Driver**: 525.0+
- **CUDA**: 11.0+ (included in go-vod image)

---

## License

MIT © 2026

---

<p align="center">
  <sub>Built with frustration and eventual success.</sub>
</p>
