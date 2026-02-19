# ---------------------------------------------------------------------------
# Base: Ubuntu 22.04 LTS (Jammy Jellyfish) for s390x
#
# Why Ubuntu 22.04 instead of UBI9 / ubi-minimal:
#   The Gold-Bull s390x runner tarball bundles a .NET 8 runtime whose
#   libhostfxr.so was compiled with GCC 12 and requires GLIBCXX_3.4.30.
#   UBI 9 ships GCC 11 → libstdc++.so.6.0.29 → max symbol GLIBCXX_3.4.29.
#   Fedora 36/37 provide libstdc++.so.6.0.30 but it requires GLIBC_2.35/2.36
#   which UBI 9 (glibc 2.34) cannot satisfy.
#   gcc-toolset-12-libstdc++ (runtime) is not packaged for s390x on any EL9
#   distro (only headers/devel packages are provided on s390x).
#
#   Ubuntu 22.04 LTS ships:
#     glibc 2.35           (satisfies libstdc++ 6.0.30's GLIBC_2.35 requirement)
#     libstdc++6 12.3.0    → libstdc++.so.6.0.30 → provides GLIBCXX_3.4.30 ✓
#   This is fully OCI-compliant and runs correctly on OpenShift / Kubernetes.
# ---------------------------------------------------------------------------
FROM ubuntu:22.04

ARG RUNNER_VERSION
ARG RUNNER_DOWNLOAD_URL
ARG RUNNER_DOWNLOAD_SHA256

ENV RUNNER_HOME=/home/runner \
    RUNNER_ALLOW_RUNASROOT=1 \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      tar \
      gzip \
      unzip \
      openssl \
      locales \
      findutils \
      procps \
      libicu70 \
      libstdc++6 && \
    locale-gen en_US.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Verify libstdc++.so.6.0.30 is present → guarantees GLIBCXX_3.4.30 (fails build fast if not)
RUN test -f /usr/lib/s390x-linux-gnu/libstdc++.so.6.0.30 && \
    echo "libstdc++.so.6.0.30 present → GLIBCXX_3.4.30 confirmed"

RUN useradd -m -d ${RUNNER_HOME} -u 1001 runner
WORKDIR ${RUNNER_HOME}

RUN curl -fL "${RUNNER_DOWNLOAD_URL}" -o runner.tar.gz && \
    if [ -n "${RUNNER_DOWNLOAD_SHA256}" ]; then \
      echo "${RUNNER_DOWNLOAD_SHA256}  runner.tar.gz" | sha256sum -c -; \
    fi && \
    tar -xzf runner.tar.gz && \
    rm -f runner.tar.gz && \
    ./bin/installdependencies.sh || true

# Ensure k8s container hooks are present (bundled in tarball since runner v2.304+)
RUN test -f ${RUNNER_HOME}/k8s/index.js || echo "WARNING: k8s container hooks not found in runner tarball"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && \
    chmod +x ${RUNNER_HOME}/run.sh && \
    chown -R runner:runner ${RUNNER_HOME}

USER 1001
ENTRYPOINT ["/home/runner/run.sh"]

