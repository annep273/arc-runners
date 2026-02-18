# Product Requirements Document (PRD)

## Title
ARC runner deployment for OpenShift on s390x with GHES GitHub App authentication

## Objective
Provide a reproducible, enterprise-friendly deployment pattern for GitHub Actions runners on OpenShift `linux/s390x` using Actions Runner Controller (ARC), with separate build/install scripts and private-registry support.

## Problem statement
Organizations running OpenShift on IBM Z (`s390x`) need self-hosted GitHub Actions runners integrated with GHES. Official ARC-related images and binaries are not consistently available for `s390x`, requiring a controlled custom-build approach.

## Goals

1. Produce required ARC images for `s390x` (controller, runner, optional dind runner).
2. Push built images to an enterprise registry.
3. Provide separate install scripts for:
   - GitHub App auth secret
   - ARC controller
   - Runner scale set
4. Support GHES GitHub App-based authentication.
5. Document architecture decisions, risks, assumptions, and rollout steps.

## Non-goals

- Multi-cluster fleet management automation.
- Advanced observability stack deployment.
- End-user workflow migration.

## Users

- Platform engineers administering OpenShift.
- DevOps engineers managing CI runner pools.
- Security/compliance teams requiring controlled artifact flow.

## Functional requirements

1. Build scripts must support parameterized image name/tag/registry.
2. Runner image build must support configurable `linux/s390x` runner artifact URL and optional SHA-256 verification.
3. Install scripts must be idempotent (`helm upgrade --install`, `oc apply`/safe secret recreation).
4. GHES GitHub App secret creation must support private key from file path.
5. Helm installs must allow image override to private registry.

## Non-functional requirements

- Script execution in standard POSIX shell environment on admin workstation.
- Secrets never printed in logs.
- Compatible with OpenShift namespaces and pull secret model.

## Constraints

- Official image manifests tested include `amd64/arm64` only for key ARC images.
- `s390x` runner uses configurable source and may rely on community-maintained artifacts.
- OpenShift SCC/privilege policies may restrict DIND mode.

## Success criteria

- All required images exist in private registry with `linux/s390x` manifest.
- ARC controller and runner scale set are deployed and reconciled successfully.
- Test workflow job executes on `s390x` runner labels.

## Risks

1. Upstream support mismatch for `s390x` runner binaries.
2. Security/compliance concerns with community binary provenance.
3. Privileged container restrictions for DIND mode on OpenShift.

## Mitigations

- Add SHA-256 validation and artifact pinning.
- Keep binary source configurable for internal approved mirrors.
- Prefer Kubernetes mode over DIND in restricted clusters.

## Deliverables

- Research summary and support matrix.
- PRD + design docs.
- Build/install scripts.
- Helm values templates for private registry + GHES auth.
