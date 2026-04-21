# Releasing

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Tag pushes trigger `.github/workflows/release.yml`, which builds a
`.tar.gz` archive and creates a GitHub Release.

## Version bumping rules

- **Patch** (`1.0.0` → `1.0.1`): doc fixes, script hardening, clearer
  error messages — no changes to `.env` keys or command interface.
- **Minor** (`1.0.0` → `1.1.0`): new subcommand, new `.env` keys with
  defaults, new supported GPU family, extra verification steps.
- **Major** (`1.x.x` → `2.0.0`): breaking changes — renamed
  subcommands, required new `.env` keys, bumped upstream Memories /
  go-vod / NVIDIA-toolkit minimums that break existing installs.

## Cutting a release

1. Update `VERSION` file with the new version (no leading `v`):
   ```bash
   echo "1.1.0" > VERSION
   ```
2. Move unreleased entries in `CHANGELOG.md` under a new `[1.1.0]`
   heading with today's date. Update the compare links at the bottom.
3. Commit + push:
   ```bash
   git add VERSION CHANGELOG.md
   git commit -m "Release 1.1.0"
   git push
   ```
4. Tag + push:
   ```bash
   git tag -a v1.1.0 -m "Release 1.1.0"
   git push origin v1.1.0
   ```
   The workflow triggers automatically and creates the GitHub Release
   with the archive attached.

5. Verify: https://github.com/jimnoneill/nextcloud-memories-gpu/releases

## Install-from-release one-liner

End users install a tagged release with:

```bash
curl -fsSL https://github.com/jimnoneill/nextcloud-memories-gpu/releases/latest/download/nextcloud-memories-gpu-v1.0.0.tar.gz | tar xz
```

## Manual workflow dispatch

If a tag already exists but the workflow failed (e.g., transient
GitHub outage), re-run via:

```bash
gh workflow run release.yml -f tag=v1.0.0
```
