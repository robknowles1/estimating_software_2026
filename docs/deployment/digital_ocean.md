# Digital Ocean Deployment Runbook

Deployment uses **Kamal 2** (bundled with Rails 8.1). All environments run on Digital Ocean Droplets.

---

## Environments

| Environment | Droplet              | IP             | URL                        | Registry                              |
|-------------|----------------------|----------------|----------------------------|---------------------------------------|
| Staging     | ubuntu-s-1vcpu-1gb-amd-sfo3 | 64.23.238.38 | http://64.23.238.38:3000 | ghcr.io/robknowles1/estimating_software_2026 |
| Syndicate   | ubuntu-s-1vcpu-1gb-sfo3-01  | 147.182.199.74 | syndicate-development.com | (separate — not this project) |
| Production  | TBD                  | TBD            | TBD                        | ghcr.io/robknowles1/estimating_software_2026 |

---

## Architecture

- **Kamal proxy** runs on the Droplet alongside the app container.
- **Postgres 16** runs as a Kamal accessory container (`estimating-software-staging-db`).
- The app reaches Postgres via Docker network hostname (`DB_HOST=estimating-software-staging-db`), not `127.0.0.1`.
- The staging Droplet is **dedicated** to this app. There is no Nginx or any other service holding ports 80 or 443 — those ports are free. Kamal proxy is currently configured to listen on 3000/3001; switching to 80/443 requires only a `proxy.run` config change and a `bin/kamal proxy reboot -d staging`.

---

## GitHub Secrets Required

Set these in **Settings → Secrets → Actions** on the repo. All five are already configured.

| Secret name                                  | Value source                                         |
|----------------------------------------------|------------------------------------------------------|
| `RAILS_MASTER_KEY`                           | Contents of `config/master.key` (never commit this)  |
| `KAMAL_REGISTRY_PASSWORD`                    | GitHub PAT with `write:packages` scope               |
| `ESTIMATING_SOFTWARE_2026_DATABASE_PASSWORD` | Strong random password (generate once, store safely) |
| `SEED_ADMIN_PASSWORD`                        | Initial admin password for staging                   |
| `DEPLOY_SSH_PRIVATE_KEY`                     | Private key whose public half is in `~/.ssh/authorized_keys` on the Droplet |

---

## First-Time Setup (Staging)

> **Status:** `bin/kamal setup -d staging` has already been run against `64.23.238.38` and the app is live.
>
> **If rebuilding the Droplet from scratch**, you must run `bin/kamal setup -d staging` again (step 4 below) before any other Kamal commands will work. The steps below document exactly what that requires.

### 1. Add your SSH public key to the Droplet

```bash
ssh-copy-id root@64.23.238.38
```

Or paste the public key into DO console → Settings → Security → SSH Keys.

### 2. Export secrets locally

```bash
export RAILS_MASTER_KEY=$(cat config/master.key)
export KAMAL_REGISTRY_PASSWORD=<your-github-pat>
export ESTIMATING_SOFTWARE_2026_DATABASE_PASSWORD=<db-password>
export SEED_ADMIN_PASSWORD=<initial-admin-password>
```

### 3. Authenticate with GHCR

```bash
echo $KAMAL_REGISTRY_PASSWORD | docker login ghcr.io -u robknowles1 --password-stdin
```

### 4. Run Kamal setup

```bash
bin/kamal setup -d staging
```

This installs Docker on the Droplet, pulls and starts the proxy, Postgres accessory, and app container, then runs `db:prepare` + seeds.

The first boot takes ~2–3 minutes on a 1 vCPU Droplet — this is normal.

### 5. Verify

```bash
curl http://64.23.238.38:3000/up
# => HTTP 200
```

Log in with `admin@example.com` / `$SEED_ADMIN_PASSWORD`.

---

## Routine Deploy (Staging)

After `setup` has run once, all subsequent deploys happen automatically via GitHub Actions when code is merged to `main`. The `deploy_staging` job in `.github/workflows/ci.yml` runs after all CI checks pass.

To deploy manually from your local machine:

```bash
export RAILS_MASTER_KEY=$(cat config/master.key)
export KAMAL_REGISTRY_PASSWORD=<your-github-pat>
export ESTIMATING_SOFTWARE_2026_DATABASE_PASSWORD=<db-password>
export SEED_ADMIN_PASSWORD=<admin-password>

bin/kamal deploy -d staging
```

---

## Useful Kamal Commands (Staging)

```bash
# Tail app logs
bin/kamal logs -d staging -f

# Rails console
bin/kamal console -d staging

# App shell
bin/kamal shell -d staging

# Database console
bin/kamal dbc -d staging

# Release a stuck deploy lock
bin/kamal lock release -d staging

# Reboot the proxy (e.g. after changing proxy.run config)
bin/kamal proxy reboot -d staging

# Check running containers on the Droplet
ssh root@64.23.238.38 docker ps
```

---

## Troubleshooting

### Health check timeout

The app container has 120 seconds (`deploy_timeout: 120`) to pass its health check (`GET /up`). On a cold start (no cached layers) this can be tight. If it fails:

1. Check that the Postgres accessory is running: `ssh root@64.23.238.38 docker ps`
2. Check app logs: `bin/kamal logs -d staging`
3. Release the lock if needed: `bin/kamal lock release -d staging`

### "Cannot connect to database" / Unix socket error

The app must reach Postgres over TCP. Verify `DB_HOST` is set to the accessory container name (`estimating-software-staging-db`) and that `database.yml` has `host: <%= ENV["DB_HOST"] %>`.

### Image not updated after code change

Kamal tags images by git SHA. Uncommitted changes are invisible to Kamal — commit before deploying.

### Deploy lock stuck

A failed deploy can leave a lock: `bin/kamal lock release -d staging`

---

## Production Setup (Future)

Production will follow the same pattern on a separate Droplet. Update `config/deploy.yml` with the production Droplet IP before running `bin/kamal setup` (no `-d` flag defaults to production).
