# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] — 2026-04-21

Initial public release.

### Added
- `deploy.sh` one-shot installer with five subcommands:
  `storage`, `gpu`, `nextcloud`, `status`, `logs`
- NFS export configuration on the storage server (read-only to GPU host)
- `go-vod` Docker deployment on the GPU server using the
  `radialapps/go-vod` image with NVENC + NVIDIA runtime
- Nextcloud Memories occ configuration (external transcoder,
  NVENC on, VA-API off, quality/timeout tunables)
- PHP + nginx FastCGI timeout extensions to prevent long-playing
  videos from 408'ing
- GOP-workaround reminder banner after `nextcloud` step
  (without it, videos stop after 5 seconds)
- `.env.example` with required variables documented
- Docs: `configuration.md`, `troubleshooting.md`, `manual-setup.md`,
  `admin-ui.md`
- `VERSION` file (single source of truth for `./deploy.sh version`)

### Requirements
- Ubuntu 22.04+ on both hosts
- NVIDIA driver 525+ / CUDA 11+ on GPU host
- Docker + NVIDIA Container Toolkit on GPU host
- Nextcloud Memories 7.0+
- `go-vod` 0.2.6+ (via `radialapps/go-vod:latest`)

[Unreleased]: https://github.com/jimnoneill/nextcloud-memories-gpu/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/jimnoneill/nextcloud-memories-gpu/releases/tag/v1.0.0
