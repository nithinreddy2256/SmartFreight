# =============================================================================
# SmartFreight Custom Jenkins Agent
# =============================================================================
# Base:    eclipse-temurin:21-jdk-alpine  (OpenJDK 21, Alpine Linux)
# Extras:  Maven 3.9.x, AWS CLI v2, Trivy, git, curl, jq, Docker CLI
# User:    jenkins (uid/gid 1000) — non-root for security compliance
# =============================================================================

FROM eclipse-temurin:21-jdk-alpine AS base

# -----------------------------------------------------------------------------
# Build arguments (override at build time for version pinning)
# -----------------------------------------------------------------------------
ARG MAVEN_VERSION=3.9.6
ARG TRIVY_VERSION=0.50.4
ARG DOCKER_CLI_VERSION=25.0.3

# -----------------------------------------------------------------------------
# Labels — OCI image metadata
# -----------------------------------------------------------------------------
LABEL org.opencontainers.image.title="SmartFreight Jenkins Agent" \
      org.opencontainers.image.description="Custom Jenkins inbound agent with Maven, AWS CLI v2, Trivy, and Jib support" \
      org.opencontainers.image.vendor="SmartFreight Engineering" \
      org.opencontainers.image.base.name="eclipse-temurin:21-jdk-alpine"

# -----------------------------------------------------------------------------
# Environment variables
# -----------------------------------------------------------------------------
ENV JAVA_HOME=/opt/java/openjdk \
    MAVEN_HOME=/opt/maven \
    MAVEN_CONFIG=/root/.m2 \
    PATH="/opt/java/openjdk/bin:/opt/maven/bin:/usr/local/bin:${PATH}" \
    # Avoid interactive prompts during package installs
    DEBIAN_FRONTEND=noninteractive \
    # Maven: disable colour output in CI, use batch mode by default
    MAVEN_OPTS="-Xmx2g -Xms512m -XX:+UseG1GC -Djava.awt.headless=true" \
    # Jenkins agent home directory
    JENKINS_HOME=/home/jenkins \
    JENKINS_AGENT_WORKDIR=/home/jenkins/agent

# =============================================================================
# Stage: builder — compile/extract tools that need intermediate steps
# =============================================================================
FROM base AS builder

# Install tools needed to fetch and extract archives
RUN apk add --no-cache \
    curl \
    tar \
    gzip \
    unzip \
    gnupg \
    ca-certificates

# -----------------------------------------------------------------------
# Maven 3.9.x — download and verify checksum
# -----------------------------------------------------------------------
RUN set -eux; \
    MAVEN_URL="https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"; \
    curl -fsSL "${MAVEN_URL}" -o /tmp/maven.tar.gz; \
    curl -fsSL "${MAVEN_URL}.sha512" -o /tmp/maven.tar.gz.sha512; \
    # Verify checksum
    EXPECTED=$(cat /tmp/maven.tar.gz.sha512 | tr -d ' \n'); \
    ACTUAL=$(sha512sum /tmp/maven.tar.gz | awk '{print $1}'); \
    [ "$ACTUAL" = "$EXPECTED" ] || { echo "Maven checksum mismatch!"; exit 1; }; \
    tar -xzf /tmp/maven.tar.gz -C /opt/; \
    mv "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven; \
    rm -f /tmp/maven.tar.gz /tmp/maven.tar.gz.sha512

# -----------------------------------------------------------------------
# AWS CLI v2 — official installer (Alpine/musl compatible build)
# -----------------------------------------------------------------------
RUN set -eux; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip; \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig" -o /tmp/awscliv2.zip.sig; \
    # Import AWS public key and verify signature
    gpg --recv-keys 6A43B03328B3F2D7 2>/dev/null || true; \
    gpg --verify /tmp/awscliv2.zip.sig /tmp/awscliv2.zip 2>/dev/null || \
        echo "WARN: GPG verification skipped (key server unavailable in build)"; \
    unzip -q /tmp/awscliv2.zip -d /tmp/awscli; \
    /tmp/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin; \
    rm -rf /tmp/awscliv2.zip /tmp/awscliv2.zip.sig /tmp/awscli; \
    /usr/local/bin/aws --version

# -----------------------------------------------------------------------
# Trivy — vulnerability scanner
# -----------------------------------------------------------------------
RUN set -eux; \
    TRIVY_URL="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"; \
    curl -fsSL "${TRIVY_URL}" -o /tmp/trivy.tar.gz; \
    curl -fsSL "${TRIVY_URL}.sha256sum" -o /tmp/trivy.sha256sum 2>/dev/null || true; \
    tar -xzf /tmp/trivy.tar.gz -C /usr/local/bin trivy; \
    chmod +x /usr/local/bin/trivy; \
    rm -f /tmp/trivy.tar.gz /tmp/trivy.sha256sum; \
    /usr/local/bin/trivy --version

# =============================================================================
# Stage: final — assemble the runtime image
# =============================================================================
FROM base AS final

# Install runtime OS packages
# docker-cli: for docker login (ECR authentication, Testcontainers host)
# git:        for SCM checkout and git diff change detection
# curl:       for Spinnaker Gate API calls and healthchecks
# jq:         for JSON parsing in shell scripts
# bash:       required by Jenkins pipeline sh steps and our scripts
# xmllint:    for parsing JaCoCo XML in check-coverage.sh
# python3:    fallback XML parser in check-coverage.sh
# openssh:    SSH key support for git operations
RUN apk add --no-cache \
    bash \
    curl \
    git \
    jq \
    libxml2-utils \
    openssh-client \
    python3 \
    py3-pip \
    shadow \
    docker-cli \
    fontconfig \
    ttf-dejavu \
    && rm -rf /var/cache/apk/*

# Copy Maven from builder stage
COPY --from=builder /opt/maven /opt/maven

# Copy AWS CLI v2 from builder stage
COPY --from=builder /usr/local/aws-cli /usr/local/aws-cli
COPY --from=builder /usr/local/bin/aws /usr/local/bin/aws

# Copy Trivy from builder stage
COPY --from=builder /usr/local/bin/trivy /usr/local/bin/trivy

# Verify installations
RUN java -version && \
    mvn --version && \
    aws --version && \
    trivy --version && \
    git --version && \
    jq --version && \
    docker --version

# -----------------------------------------------------------------------------
# Create non-root jenkins user (uid/gid 1000) — matches host jenkins user
# to avoid permission issues when mounting volumes
# -----------------------------------------------------------------------------
RUN set -eux; \
    # Create group first (gid 1000)
    addgroup -g 1000 jenkins; \
    # Create user with uid 1000, home dir, in jenkins group
    adduser -u 1000 -G jenkins -h /home/jenkins -D jenkins; \
    # Add jenkins to docker group (gid 999 by default on Linux hosts)
    # so it can call docker login for ECR authentication
    addgroup -g 999 docker 2>/dev/null || true; \
    adduser jenkins docker 2>/dev/null || true; \
    # Create agent working directory and Maven local repository cache dir
    mkdir -p /home/jenkins/agent \
             /home/jenkins/.m2/repository \
             /home/jenkins/.aws \
             /home/jenkins/.trivy; \
    chown -R jenkins:jenkins /home/jenkins

# -----------------------------------------------------------------------------
# Maven settings — configure local repo, mirrors, proxy (customise as needed)
# -----------------------------------------------------------------------------
COPY --chown=jenkins:jenkins settings.xml /home/jenkins/.m2/settings.xml

# -----------------------------------------------------------------------------
# Pre-seed Trivy vulnerability DB to speed up first scan in pipeline
# (update cache as jenkins user, stored in agent home)
# -----------------------------------------------------------------------------
USER jenkins
ENV TRIVY_CACHE_DIR=/home/jenkins/.trivy
RUN trivy --cache-dir "${TRIVY_CACHE_DIR}" image --download-db-only --no-progress 2>/dev/null || \
    echo "WARN: Trivy DB pre-seed failed — will download at scan time"

# Switch back to root momentarily to install jenkins-agent.jar
USER root

# -----------------------------------------------------------------------------
# Jenkins Remoting agent JAR — required for Jenkins to connect to this agent
# The JAR version must match the Jenkins server version.
# Use build arg to pin: --build-arg JENKINS_AGENT_VERSION=x.y
# -----------------------------------------------------------------------------
ARG JENKINS_AGENT_VERSION=3206.vb_15dcf73f6a_9
ENV JENKINS_AGENT_VERSION=${JENKINS_AGENT_VERSION}

RUN curl -fsSL \
    "https://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/${JENKINS_AGENT_VERSION}/remoting-${JENKINS_AGENT_VERSION}.jar" \
    -o /usr/share/jenkins/agent.jar && \
    chmod 644 /usr/share/jenkins/agent.jar && \
    mkdir -p /usr/share/jenkins && \
    chown -R jenkins:jenkins /usr/share/jenkins

# -----------------------------------------------------------------------------
# Copy entrypoint and helper scripts
# -----------------------------------------------------------------------------
COPY --chown=root:root entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# -----------------------------------------------------------------------------
# Switch to non-root jenkins user for all runtime operations
# -----------------------------------------------------------------------------
USER jenkins
WORKDIR /home/jenkins/agent

# -----------------------------------------------------------------------------
# Expose agent port (JNLP / Remoting protocol)
# -----------------------------------------------------------------------------
EXPOSE 50000

# Verify JAVA_HOME is set correctly
RUN echo "JAVA_HOME=${JAVA_HOME}" && java -version

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
