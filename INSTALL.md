---
post_title: "MultiChain Docker Installer"
author1: "leodyversemilla07"
post_slug: multichain-docker-installer
microsoft_alias: leodyver
featured_image: https://www.multichain.com/img/multichain-logo.png
categories: [docker, devops]
tags: [multichain, installer, docker, compose]
ai_note: "Assisted by AI; validated by author."
summary: "Bash and PowerShell installers to create a .env and optionally bring up the MultiChain compose stack (masternode + explorer)."
post_date: 2025-08-23
---

## Installer (install.sh)

This repository uses `install.sh` as the primary and supported installer. `install.sh` prepares a `.env` for the compose stack and can optionally start the core services (`masternode` and `explorer`). Run `install.sh` on Linux, macOS, WSL, or Git Bash on Windows — it is the recommended and fully supported workflow. A legacy `install.ps1` exists for historical reference only and is not recommended for new deployments.

What it does
- Reads existing `.env` values when present and uses them to prefill fields.
- Generates a secure RPC password if none is provided.
- Writes `.env` and attempts to restrict file ACLs on Windows.
- Optionally runs `docker compose up -d masternode explorer`.


Quick examples

Using the provided bash installer (recommended for Unix / WSL / Git Bash / Linux hosts):

  # interactive (prompts for missing values)
  ./install.sh --start

  # non-interactive
  ./install.sh -c procuchain -u multichainrpc -p S3cret -s

  # force overwrite
  ./install.sh -f -s

Use `install.sh` exclusively for installation and first-boot automation; the rest of this document assumes the `.env` was created by `install.sh`.

Notes
- The script tries to use `docker compose` (Compose V2) and falls back to `docker-compose` if needed.
- The script only starts `masternode` and `explorer` by default to speed up first-boot. You can bring other services up via `docker compose up -d`.
- For production, consider injecting secrets with Docker secrets or files and set `RPC_PASSWORD_FILE` instead of the plaintext `.env` value.

Next steps / Troubleshooting
- If `docker compose` isn't found, install Docker Desktop or the Compose plugin.
- After starting, follow logs: `docker compose logs -f masternode`
- Explorer UI available at http://localhost:2750/ once healthy.

Requirements coverage
- Create `.env` with required variables: Done by `install.sh`.
- Generate secure RPC password if missing: Done by `install.sh` (auto-generated when omitted).
- Start core services via Compose: Optional via `--start` / `-s` when running `install.sh`.
