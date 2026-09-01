# Gitea Lab Runbook

Gitea instance running on k3d via ArgoCD. Covers setup, operations, and usage for both admins and developers.

---

## Table of Contents

- [Architecture](#architecture)
- [Access](#access)
- [Admin Operations](#admin-operations)
- [SSH Setup](#ssh-setup)
- [Developer Guide](#developer-guide)
- [Gitea Actions](#gitea-actions)
- [Troubleshooting](#troubleshooting)

---

## Architecture

```
k3d cluster
  └── ArgoCD
        ├── gitea (namespace: gitea)
        │     ├── gitea pod
        │     ├── postgresql-ha (3 pods)
        │     └── valkey-cluster (3 pods)
        └── gitea-runner (namespace: gitea)
              └── gitea-runner-runner-0 (StatefulSet)
                    ├── runner container (gitea act-runner v3.0.2)
                    └── dind sidecar (docker:29.7.1-dind)
```

**Ports**

| Service | Internal | Host |
|---|---|---|
| Gitea HTTP | 3000 | 8080 (via Traefik) |
| Gitea HTTPS | 3000 | 8443 (via Traefik) |
| Gitea SSH | 22 | 2222 (NodePort 30022) |

**URLs**

```
HTTP:   http://gitea.localhost:8080
HTTPS:  https://gitea.localhost:8443
SSH:    ssh://git@127.0.0.1:2222
```

**ArgoCD Applications**

```
experiments/gitea/gitea.yaml         → Gitea + PostgreSQL + Valkey
experiments/gitea/runner.yaml        → Gitea Actions runner
```

---

## Access

### Web UI

```
URL:      http://gitea.localhost:8080
Username: gitea-admin
Password: admin1234
```

### Git over HTTPS

```bash
git clone http://gitea-admin:admin1234@gitea.localhost:8080/<user>/<repo>.git
```

### Git over SSH

See [SSH Setup](#ssh-setup) below.

---

## Admin Operations

### Reset admin password

```bash
kubectl exec -it -n gitea \
  $(kubectl get pod -n gitea -l app.kubernetes.io/name=gitea -o name | head -1) -- \
  gitea admin user change-password --username gitea-admin --password <newpassword>
```

### Create a new user

```bash
kubectl exec -it -n gitea \
  $(kubectl get pod -n gitea -l app.kubernetes.io/name=gitea -o name | head -1) -- \
  gitea admin user create \
    --username <username> \
    --password <password> \
    --email <email> \
    --must-change-password=false
```

### List users

```bash
kubectl exec -it -n gitea \
  $(kubectl get pod -n gitea -l app.kubernetes.io/name=gitea -o name | head -1) -- \
  gitea admin user list
```

### Check runner registration token

```
http://gitea.localhost:8080/-/admin/runners
→ Create new Runner → copy token
```

### Update runner token secret

```bash
kubectl create secret generic gitea-runner-secret \
  --from-literal=runner-token=<new-token> \
  -n gitea \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart runner to re-register
kubectl rollout restart statefulset gitea-runner-runner -n gitea
```

### Check runner status

```bash
# Pod status
kubectl get pods -n gitea

# Runner logs
kubectl logs -n gitea gitea-runner-runner-0 -c runner -f

# Runner registered labels
kubectl logs -n gitea gitea-runner-runner-0 -c runner | grep "declare successfully"
```

### Rebuild cluster (destructive)

Required when changing k3d port mappings:

```bash
k3d cluster delete lab
make build-k3d-self-signed
make init-self-signed-k3d-argo
```

---

## SSH Setup

### Prerequisites

- Cluster must be running with NodePort 30022 mapped to host port 2222
- Your SSH public key must be added to your Gitea account

### Generate SSH key for Gitea

```bash
ssh-keygen -t ed25519 -C "gitea-lab" -f ~/gitea
```

### Add public key to Gitea

```
http://gitea.localhost:8080/user/settings/keys
→ Add Key → paste contents of ~/gitea.pub
```

### Configure SSH client

Add to `~/.ssh/config`:

```
Host gitea.localhost
  HostName 127.0.0.1
  Port 2222
  IdentityFile ~/gitea
  User git
```

### Test SSH connection

```bash
ssh -T git@gitea.localhost
# Should return: Hi <username>! You've successfully authenticated...
```

### Clone via SSH

```bash
git clone git@gitea.localhost:<user>/<repo>.git
```

### If SSH port is not mapped (port-forward workaround)

```bash
# Start port-forward in background
kubectl port-forward svc/gitea-ssh 2222:22 -n gitea &

# Clone
git -c core.sshCommand="ssh -i ~/gitea -p 2222" \
  clone ssh://git@127.0.0.1:2222/<user>/<repo>.git
```

---

## Developer Guide

### Create a repository

```
http://gitea.localhost:8080/repo/create
```

Or via API:

```bash
curl -X POST http://gitea.localhost:8080/api/v1/user/repos \
  -H "Content-Type: application/json" \
  -u gitea-admin:admin1234 \
  -d '{"name":"my-repo","private":false,"auto_init":true}'
```

### Clone a repository

```bash
# HTTPS
git clone http://gitea-admin:admin1234@gitea.localhost:8080/gitea-admin/my-repo.git

# SSH (after SSH setup)
git clone git@gitea.localhost:gitea-admin/my-repo.git
```

### Push code

```bash
git add .
git commit -m "feat: my change"
git push origin main
```

### Store credentials to avoid retyping

```bash
git config --global credential.helper store
# Enter credentials once on next push — stored in ~/.git-credentials
```

### Use an access token instead of password

```
http://gitea.localhost:8080/user/settings/applications
→ Generate Token → copy token
```

```bash
git remote set-url origin http://gitea-admin:<token>@gitea.localhost:8080/gitea-admin/my-repo.git
```

---

## Gitea Actions

### Overview

Gitea Actions is GitHub Actions-compatible. Workflows live in `.gitea/workflows/` in your repo.

**Runner labels available:**

```
ubuntu-latest
ubuntu-24.04
ubuntu-22.04
```

### Basic workflow

```yaml
# .gitea/workflows/ci.yaml
name: CI

on:
  push:
    branches:
      - main
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run tests
        run: |
          echo "Running on $(hostname)"
          # your commands here
```

### View workflow runs

```
http://gitea.localhost:8080/<user>/<repo>/actions
```

### View runner status

```
http://gitea.localhost:8080/-/admin/runners
```

### Runner uses Docker-in-Docker

The runner has a DinD sidecar — Docker commands work natively in workflows:

```yaml
steps:
  - name: Build image
    run: docker build -t myapp .

  - name: Run container
    run: docker run --rm myapp echo "hello"
```

### Differences from GitHub Actions

| GitHub Actions | Gitea Actions |
|---|---|
| `.github/workflows/` | `.gitea/workflows/` |
| `github.com` actions | Same actions work (fetched from GitHub) |
| `GITHUB_*` vars | `GITEA_*` vars (also supports `GITHUB_*`) |
| Hosted runners | Self-hosted only |

---

## Troubleshooting

### Can't log in to web UI

```bash
# Reset password directly
kubectl exec -it -n gitea \
  $(kubectl get pod -n gitea -l app.kubernetes.io/name=gitea -o name | head -1) -- \
  gitea admin user change-password --username gitea-admin --password admin1234
```

Note: Gitea only reads the `admin.password` helm value on first install. Use the kubectl command above to reset after initial setup.

### Git push authentication failed

```bash
# Verify credentials work via API
curl -u gitea-admin:admin1234 http://gitea.localhost:8080/api/v1/user

# If 401 — password is wrong, reset via kubectl exec above
# If 200 — credentials are correct, check remote URL
git remote -v
```

### Runner not picking up jobs

```bash
# Check runner is online
kubectl logs -n gitea gitea-runner-runner-0 -c runner | tail -20

# Check runner is registered
http://gitea.localhost:8080/-/admin/runners
# Should show lab-runner as Online

# Check workflow uses correct label
# runs-on: ubuntu-latest (not ubuntu, not Linux)
```

### Runner init container stuck

```bash
# Check what URL it's trying
kubectl logs -n gitea gitea-runner-runner-0 -c reach-gitea

# If showing gitea.localhost — URL is wrong, update Application spec
# giteaRootURL should be: http://gitea-http.gitea.svc.cluster.local:3000
```

### SSH connection refused

```bash
# Check SSH port is mapped
docker ps | grep k3d | grep 2222

# If not mapped — use port-forward
kubectl port-forward svc/gitea-ssh 2222:22 -n gitea &

# Check SSH service
kubectl get svc gitea-ssh -n gitea
```

### Gitea pod not starting

```bash
# Check pod status
kubectl describe pod -n gitea -l app.kubernetes.io/name=gitea

# Check PostgreSQL is healthy
kubectl get pods -n gitea | grep postgresql

# Check PVCs are bound
kubectl get pvc -n gitea
```

### ArgoCD showing Gitea as OutOfSync

```bash
# Force sync
kubectl patch application gitea -n argocd \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{}}}}}'

# Check for ignoreDifferences needed
kubectl get application gitea -n argocd -o yaml | grep -A10 "ignoreDifferences"
```

---

## Key Files

```
experiments/gitea/gitea.yaml      ArgoCD Application — Gitea + deps
experiments/gitea/runner.yaml     ArgoCD Application — Actions runner
config/k3d-cluster-self-signed.yaml  k3d cluster config (port mappings)
```

## Useful Commands

```bash
# Watch all gitea pods
kubectl get pods -n gitea -w

# Tail runner logs
kubectl logs -n gitea gitea-runner-runner-0 -c runner -f

# Exec into gitea pod
kubectl exec -it -n gitea \
  $(kubectl get pod -n gitea -l app.kubernetes.io/name=gitea -o name | head -1) -- bash

# Check gitea version
kubectl exec -it -n gitea \
  $(kubectl get pod -n gitea -l app.kubernetes.io/name=gitea -o name | head -1) -- \
  gitea --version

# List all repos via API
curl -u gitea-admin:admin1234 \
  http://gitea.localhost:8080/api/v1/repos/search | python3 -m json.tool | grep full_name
```
