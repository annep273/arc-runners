# Runbook: ARC on OpenShift s390x

## Day-0: Initial deployment

### 1. Prepare credentials

1. Create a GitHub App in your GHES instance:
   - Organization settings → Developer settings → GitHub Apps → New GitHub App
   - Permissions required:
     - **Repository permissions**: Actions (read), Metadata (read)
     - **Organization permissions**: Self-hosted runners (read/write)
   - Generate a private key and save to `secrets/github-app.pem`
   - Note the App ID and Installation ID

2. Edit `.env` with your values:
   - `REGISTRY_HOST`, `REGISTRY_NAMESPACE` — your private registry
   - `GITHUB_CONFIG_URL` — your GHES org or repo URL
   - `GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`
   - `GITHUB_APP_PRIVATE_KEY_PATH` — path to the PEM file

3. Log in to your registry:
   ```bash
   docker login ${REGISTRY_HOST}
   ```

4. Log in to OpenShift:
   ```bash
   oc login --server=https://api.your-cluster.example.com:6443
   ```

### 2. Build and push images

```bash
chmod +x scripts/build/*.sh scripts/install/*.sh scripts/validate.sh scripts/lib/common.sh
./scripts/build/build-all-images.sh
```

This builds three images for `linux/s390x`:
- Controller image
- Runner image
- Runner DIND image (optional)

### 3. Install components

```bash
# Create GitHub App secret
./scripts/install/install-github-app-secret.sh

# (Optional) Create registry pull secret
./scripts/install/install-registry-pull-secret.sh

# Install ARC controller
./scripts/install/install-controller.sh

# Install runner scale set
./scripts/install/install-runner-scale-set.sh
```

### 4. Validate

```bash
./scripts/validate.sh
```

## Day-1: Operations

### Check controller health
```bash
oc -n arc-systems get pods
oc -n arc-systems logs deployment/arc-gha-rs-controller -f
```

### Check runner pods
```bash
oc -n arc-runners get pods
oc -n arc-runners get autoscalingrunnersets
oc -n arc-runners get ephemeralrunners
```

### Check listener status
```bash
oc -n arc-runners get pods -l actions.github.com/component=listener
oc -n arc-runners logs -l actions.github.com/component=listener -f
```

### Trigger a test workflow
Create a workflow in your GHES repo:
```yaml
name: Test s390x runner
on: workflow_dispatch
jobs:
  test:
    runs-on: arc-s390x-runners
    steps:
      - run: |
          uname -m
          echo "Hello from s390x runner!"
```

### Scale runners manually
```bash
# Check current min/max
helm -n arc-runners get values arc-s390x-runners

# Update limits
helm -n arc-runners upgrade arc-s390x-runners \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --reuse-values \
  --set minRunners=1 \
  --set maxRunners=20
```

## Day-2: Maintenance

### Upgrade runner image
1. Update `RUNNER_VERSION` and `RUNNER_DOWNLOAD_URL` in `.env`
2. Rebuild: `./scripts/build/build-runner-image.sh`
3. Update `IMAGE_TAG` in `.env`
4. Reinstall runner scale set: `./scripts/install/install-runner-scale-set.sh`

### Upgrade ARC controller
1. Update `ARC_GIT_REF` and `ARC_CONTROLLER_VERSION` in `.env`
2. Rebuild: `./scripts/build/build-controller-image.sh`
3. Update `IMAGE_TAG` in `.env`
4. Reinstall controller: `./scripts/install/install-controller.sh`

### Rotate GitHub App private key
1. Generate new key in GHES App settings
2. Save to `secrets/github-app.pem`
3. Re-run: `./scripts/install/install-github-app-secret.sh`

### Rollback
```bash
# Controller
helm -n arc-systems rollback arc

# Runner scale set
helm -n arc-runners rollback arc-s390x-runners
```

## Troubleshooting

| Symptom | Check | Fix |
|---------|-------|-----|
| Controller crash loop | `oc -n arc-systems logs deploy/arc-...` | Verify controller image is s390x, check RBAC |
| Listener not starting | `oc -n arc-runners get pods` | Verify GitHub App secret, check GHES connectivity |
| Runners not registering | Listener logs | Verify `GITHUB_CONFIG_URL`, runner image has `run.sh` |
| Image pull errors | `oc -n arc-runners get events` | Run `install-registry-pull-secret.sh`, link SA |
| SCC denied | Pod events | Use `kubernetes` mode, avoid privileged DIND |
