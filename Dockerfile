# /Dockerfile
# syntax=docker/dockerfile:1.7

# ---------------------------------------------------------------------------
# Builder stage: install everything. Layers here are throwaway; only the
# final filesystem state matters because the final stage flattens it.
# ---------------------------------------------------------------------------
FROM ubuntu:26.04 AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG RUST_TOOLCHAIN=stable
ARG PYTHON_PACKAGE=python3 python3-pip python3-venv
ARG JAVA_PACKAGE=openjdk-17-jdk
ARG ANGULAR_CLI_VERSION=latest
# GO_VERSION default: "latest" -> fetched at build time
ARG GO_VERSION=latest
ARG CLAUDE_CODE_VERSION=latest
ARG TARGETARCH

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=Europe/Rome

WORKDIR /root

# Install base deps
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    acl \
    bash-completion \
    build-essential \
    ca-certificates \
    curl \
    direnv \
    docker.io \
    git \
    gnupg \
    libbz2-dev \
    libffi-dev \
    libncurses5-dev \
    libncursesw5-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    llvm \
    pkg-config \
    ruby-dev \
    ruby-full \
    tar \
    tzdata \
    unzip \
    util-linux \
    wget \
    xz-utils \
    zlib1g-dev \
    sudo \
    tmux \
    tree \
    byobu \
    ${PYTHON_PACKAGE} ${JAVA_PACKAGE} && \
    rm -rf /var/lib/apt/lists/*

RUN ln -fs /usr/share/zoneinfo/Europe/Rome /etc/localtime && \
    echo Europe/Rome > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata

# Ensure ubuntu user exists at UID/GID 1000 (already shipped by ubuntu base images,
# but recreate defensively in case of future base-image change).
RUN if ! id -u ubuntu >/dev/null 2>&1; then \
        useradd -m -u 1000 -U -s /bin/bash ubuntu; \
    fi && \
    usermod -aG sudo ubuntu && \
    printf 'ubuntu ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/ubuntu-nopasswd && \
    chmod 0440 /etc/sudoers.d/ubuntu-nopasswd

ENV HOME=/home/ubuntu

RUN su ubuntu -l -c "git config --global user.name 'ubuntu' && git config --global user.email 'ubuntu@dev.it' && git config --global credential.helper store" && \
    HOME=/root git config --global user.name 'root' && \
    HOME=/root git config --global user.email 'root@dev.it' && \
    HOME=/root git config --global credential.helper store

# Pull the shared bashrc template (public Gitea) and install it for both ubuntu and root.
# A small "ubuntu-env" extension block is appended after the template so:
#   - PS1 from the template is preserved but extended to show the current git branch
#   - direnv is hooked into bash
RUN curl -fsSL https://gitea.adiprint.it/fabio/public-utils-scripts/raw/branch/master/.bashrc-template \
        -o /etc/skel/.bashrc-template && \
    cat <<'EOF' > /etc/skel/.bashrc-ubuntu-env-extra

# --- ubuntu-env additions (appended after shared template) ---
parse_git_branch() {
    local b
    b="$(git branch --show-current 2>/dev/null)"
    if [ -n "$b" ]; then
        printf ' (%s)' "$b"
    fi
}

# Re-render PS1 including the git branch, keeping the template's color scheme.
PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]\[\033[01;31m\]($PROMPT_TAG)\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\[\033[01;33m\]$(parse_git_branch)\[\033[00m\]\$ '
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
esac

if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook bash)"
fi
EOF

RUN cat /etc/skel/.bashrc-template /etc/skel/.bashrc-ubuntu-env-extra > /home/ubuntu/.bashrc && \
    cat /etc/skel/.bashrc-template /etc/skel/.bashrc-ubuntu-env-extra > /root/.bashrc && \
    chown ubuntu:ubuntu /home/ubuntu/.bashrc && \
    chown root:root /root/.bashrc

# System-wide PATH for all shells (login + non-login interactive) so toolchains
# work regardless of how the user enters the container (docker exec, sudo, su).
RUN cat <<'EOF' > /etc/profile.d/ubuntu-env-path.sh
# ubuntu-env: prepend toolchain paths idempotently
__cenv_add_path() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}
__cenv_add_path /usr/local/bin
__cenv_add_path /usr/local/go/bin
__cenv_add_path /usr/local/bundle/bin
__cenv_add_path /home/ubuntu/go/bin
__cenv_add_path /home/ubuntu/.local/bin
__cenv_add_path /home/ubuntu/.cargo/bin
export PATH
unset -f __cenv_add_path
export GOPATH=/home/ubuntu/go
export BUNDLE_PATH=/usr/local/bundle
EOF
RUN chmod 0644 /etc/profile.d/ubuntu-env-path.sh && \
    printf '\n# ubuntu-env: load toolchain PATH for non-login interactive shells\nif [ -r /etc/profile.d/ubuntu-env-path.sh ]; then\n    . /etc/profile.d/ubuntu-env-path.sh\nfi\n' >> /etc/bash.bashrc

# Sudo: keep toolchain paths in secure_path so `sudo <tool>` works.
RUN printf 'Defaults secure_path="/home/ubuntu/.cargo/bin:/home/ubuntu/.local/bin:/home/ubuntu/go/bin:/usr/local/bundle/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\nDefaults env_keep += "PATH GOPATH BUNDLE_PATH PROMPT_TAG"\n' > /etc/sudoers.d/ubuntu-env-path && \
    chmod 0440 /etc/sudoers.d/ubuntu-env-path && \
    visudo -c -f /etc/sudoers.d/ubuntu-env-path

# Make `su` (with or without -l) carry the toolchain PATH so `su -c <cmd>` works.
RUN sed -i \
        -e 's|^ENV_SUPATH.*|ENV_SUPATH\tPATH=/home/ubuntu/.cargo/bin:/home/ubuntu/.local/bin:/home/ubuntu/go/bin:/usr/local/bundle/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin|' \
        -e 's|^ENV_PATH.*|ENV_PATH\tPATH=/home/ubuntu/.cargo/bin:/home/ubuntu/.local/bin:/home/ubuntu/go/bin:/usr/local/bundle/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin|' \
        /etc/login.defs

# /etc/environment is read by pam_env for any PAM session (su, sudo, login),
# so non-login `su -c <cmd>` also gets the toolchain PATH.
RUN printf 'PATH="/home/ubuntu/.cargo/bin:/home/ubuntu/.local/bin:/home/ubuntu/go/bin:/usr/local/bundle/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\nGOPATH="/home/ubuntu/go"\nBUNDLE_PATH="/usr/local/bundle"\n' > /etc/environment

# Install rust for ubuntu via rustup (writes to HOME/.cargo)
RUN su ubuntu -l -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y --default-toolchain ${RUST_TOOLCHAIN}" && \
    chown -R ubuntu:ubuntu /home/ubuntu/.cargo /home/ubuntu/.rustup || true

# Install just using cargo
RUN su ubuntu -l -c "cargo install just --locked"

# Install Go (fetch latest stable if GO_VERSION=latest) and make usable by ubuntu
RUN if [ "${GO_VERSION}" = "latest" ]; then \
            GO_DIST=$(curl -fsSL https://go.dev/VERSION?m=text | head -n 1); \
    else \
      GO_DIST="go${GO_VERSION}"; \
    fi && \
        case "${TARGETARCH}" in \
            amd64) GO_ARCH=amd64 ;; \
            arm64) GO_ARCH=arm64 ;; \
            *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
        esac && \
        curl -fsSL "https://go.dev/dl/${GO_DIST}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && rm /tmp/go.tar.gz && \
    chown -R ubuntu:ubuntu /usr/local/go

# Install Node LTS globally via NodeSource (makes node/npm available system-wide)
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get update && apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Angular CLI and PM2 globally (accessible to ubuntu)
RUN npm install -g @angular/cli@${ANGULAR_CLI_VERSION} pm2

# Install Ruby/Rails package managers
RUN gem install bundler rails --no-document

# Ensure pip is available
RUN apt-get update && apt-get install -y --no-install-recommends python3-pip && \
    rm -rf /var/lib/apt/lists/* && \
    python3 -m pip --version

# Install Claude Code for the non-root user using the official native installer
RUN su ubuntu -l -c "curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_CODE_VERSION}" && \
    ln -sf /home/ubuntu/.local/bin/claude /usr/local/bin/claude

# Install OpenTofu using the official Debian installer
RUN curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh && \
        chmod +x /tmp/install-opentofu.sh && \
        /tmp/install-opentofu.sh --install-method deb && \
        rm -f /tmp/install-opentofu.sh

# Install AWS CLI v2
RUN case "${TARGETARCH}" in \
            amd64) AWS_ARCH=x86_64 ;; \
            arm64) AWS_ARCH=aarch64 ;; \
            *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
        esac && \
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip && \
        unzip /tmp/awscliv2.zip -d /tmp/awscli && \
        /tmp/awscli/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update && \
        rm -rf /tmp/awscliv2.zip /tmp/awscli

# Install kubectl from the official release channel
RUN case "${TARGETARCH}" in \
            amd64) KUBECTL_ARCH=amd64 ;;\
            arm64) KUBECTL_ARCH=arm64 ;;\
            *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
        esac && \
        KUBECTL_VERSION=$(curl -L -fsSL https://dl.k8s.io/release/stable.txt) && \
        curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl" && \
        curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl.sha256" && \
        echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check && \
        install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
        rm -f kubectl kubectl.sha256

RUN mkdir -p /workspace /usr/local/bundle

# Install Rails project dependencies during build when a Rails app is present in the build context
RUN --mount=type=bind,source=.,target=/workspace,rw \
        if [ -f /workspace/Gemfile ]; then \
            cd /workspace && BUNDLE_PATH=/usr/local/bundle bundle install; \
        else \
            echo "Skipping Rails bundle install; no Gemfile found"; \
        fi

# Allow ubuntu to read/write home, /usr/local/go, /usr/local/bundle, /workspace.
# Loosen /home/ubuntu to 0755 so other supplementary-group members added at runtime
# can still resolve paths inside the home (relevant for tools under ~/.cargo/bin).
RUN chown -R ubuntu:ubuntu /home/ubuntu /usr/local/go /usr/local/bundle /workspace && \
    chmod 0755 /home/ubuntu

# Copy runtime entrypoint that handles GRANT_PERMISSION and drops privileges to ubuntu
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# Clean caches (final filesystem state is what gets flattened)
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ---------------------------------------------------------------------------
# Final stage: scratch + one COPY of the entire builder rootfs = single
# filesystem layer. ENV/WORKDIR/ENTRYPOINT/CMD are metadata only and don't
# add layers. /proc, /sys, /dev are remounted by the container runtime.
# ---------------------------------------------------------------------------
FROM scratch

COPY --from=builder / /

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=Europe/Rome \
    HOME=/home/ubuntu \
    GOPATH=/home/ubuntu/go \
    BUNDLE_PATH=/usr/local/bundle \
    PATH=/home/ubuntu/.cargo/bin:/home/ubuntu/.local/bin:/home/ubuntu/go/bin:/usr/local/bundle/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
