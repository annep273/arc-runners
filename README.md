# ARC on OpenShift s390x

This repository provides research, planning docs, and automation scripts to deploy GitHub Actions Runner Controller (ARC) on OpenShift for `linux/s390x`.

## What is included

```
arc-runners/
├── .env                                      # Configuration (registry, versions, auth)
├── .gitignore
├── docs/
│   ├── PRD.md                                # Product requirements
│   ├── DESIGN.md                             # Architecture and design decisions
│   ├── RESEARCH.md                           # Research summary and image matrix
│   └── RUNBOOK.md                            # Day-0/1/2 operations guide
├── docker/
│   └── runner-s390x/
│       ├── Dockerfile                        # Runner image for linux/s390x
│       └── entrypoint.sh
├── helm/
│   ├── controller-values.yaml                # ARC controller Helm overrides
│   └── runner-values.yaml                    # Runner scale set Helm overrides
├── scripts/
│   ├── lib/common.sh                         # Shared helpers
│   ├── build/
│   │   ├── build-controller-image.sh         # Build controller for s390x
│   │   ├── build-runner-image.sh             # Build runner for s390x
│   │   ├── build-runner-dind-image.sh        # Build DIND runner for s390x
│   │   └── build-all-images.sh               # Build everything
│   ├── install/
│   │   ├── install-github-app-secret.sh      # Create GHES GitHub App K8s secret
│   │   ├── install-registry-pull-secret.sh   # Create registry pull secret
│   │   ├── install-controller.sh             # Helm install ARC controller
│   │   └── install-runner-scale-set.sh       # Helm install runner scale set
│   └── validate.sh                           # Pre/post-deploy validation
└── secrets/
    └── README.md                             # Instructions for private key placement
```

## Prerequisites

- `docker` with `buildx` (for cross-platform s390x image builds)
- `git`
- `oc` (OpenShift CLI, logged in to target cluster)
- `helm` (v3, OCI registry support)
- Network access from cluster to GHES and private registry
- GitHub App created in GHES with runner-management permissions

## Quick start

1. Copy `.env` and fill in your registry, GHES, and auth values.
2. Place your GitHub App private key at `secrets/github-app.pem`.
3. Build and push all images:
   ```bash
   ./scripts/build/build-all-images.sh
   ```
4. Install GitHub App secret:
   ```bash
   ./scripts/install/install-github-app-secret.sh
   ```
5. Install ARC controller:
   ```bash
   ./scripts/install/install-controller.sh
   ```
6. Install runner scale set:
   ```bash
   ./scripts/install/install-runner-scale-set.sh
   ```
7. Validate:
   ```bash
   ./scripts/validate.sh
   ```

See [docs/RUNBOOK.md](docs/RUNBOOK.md) for full operational guide.

## Important support note

Official ARC controller and runner images are published for `amd64/arm64` only. This project custom-builds all images for `s390x` using the upstream Go-based controller Dockerfile and a UBI9-based runner image with the community-maintained [Gold-Bull s390x runner tarball](https://github.com/Gold-Bull/github-actions-runner/releases).
