FROM registry.access.redhat.com/ubi9/ubi-minimal:9.5

ARG RUNNER_VERSION
ARG RUNNER_DOWNLOAD_URL
ARG RUNNER_DOWNLOAD_SHA256

ENV RUNNER_HOME=/home/runner \
    RUNNER_ALLOW_RUNASROOT=1 \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# UBI9 minimal ships curl-minimal which is sufficient for runner operations.
# Do NOT install full curl — it conflicts with curl-minimal.
RUN microdnf update -y && \
    microdnf install -y \
      ca-certificates \
      git \
      jq \
      tar \
      gzip \
      unzip \
      which \
      shadow-utils \
      openssl \
      glibc-langpack-en \
      findutils \
      procps-ng \
      libicu && \
    microdnf clean all

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
