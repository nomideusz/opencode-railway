FROM ubuntu:24.04

# Bump OpenCode here: version + sha256 of opencode-linux-x64.tar.gz
# (gh api repos/anomalyco/opencode/releases/tags/vX.Y.Z -q '.assets[]|select(.name=="opencode-linux-x64.tar.gz").digest')
ARG OPENCODE_VERSION=1.18.33
ARG OPENCODE_SHA256=e546123213ae47909a4268692aa4b94950d011afe9cac9938753a2194f1c16d5

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 PORT=8080 OPENCODE_DISABLE_AUTOUPDATE=1

# Toolbox the agent can use: git, gh, Node 22, Python 3 + uv, build tools, ripgrep, ssh server.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget gnupg git openssh-server nginx-light tmux \
      vim nano less htop ripgrep fd-find jq unzip zip tree procps sudo locales \
      python3 python3-pip python3-venv build-essential \
      iputils-ping dnsutils net-tools \
  && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends nodejs gh \
  && curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh \
  && curl -fsSL -o /tmp/oc.tgz "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x64.tar.gz" \
  && echo "${OPENCODE_SHA256}  /tmp/oc.tgz" | sha256sum -c - \
  && tar xzf /tmp/oc.tgz -C /usr/local/bin opencode && rm /tmp/oc.tgz && opencode --version \
  && ln -s /usr/bin/fdfind /usr/local/bin/fd \
  # nginx `auto` sizes from the host's 48 cores on Railway, not the container's limit.
  && sed -i 's/^worker_processes .*/worker_processes 2;/' /etc/nginx/nginx.conf \
  && mkdir -p /run/sshd \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Skeleton for the persistent home (the volume mounts empty at /root on first boot).
COPY skel/ /opt/skel/
COPY entrypoint.sh /entrypoint.sh
COPY drop-file-cache /usr/local/bin/drop-file-cache

EXPOSE 22 8080
ENTRYPOINT ["/entrypoint.sh"]
