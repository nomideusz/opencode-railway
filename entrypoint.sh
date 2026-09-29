#!/bin/bash
set -e
: "${OPENCODE_SERVER_PASSWORD:?OPENCODE_SERVER_PASSWORD is required - it is the only lock on this box}"
export OPENCODE_SERVER_USERNAME="${OPENCODE_SERVER_USERNAME:-opencode}"

# /root is a Railway volume: empty on first boot, root-owned. Seed dotfiles once
# (flag file, not per-file checks: local docker pre-copies the image's /root into a
# fresh volume, which would otherwise shadow our skel).
if [ ! -f /root/.opencode-box-seeded ]; then
  cp -af /opt/skel/. /root/ && touch /root/.opencode-box-seeded
fi
mkdir -p /root/.ssh /root/workspace && chmod 700 /root/.ssh

# Persist SSH host keys on the volume so clients don't see "host key changed" after redeploys.
mkdir -p /root/.ssh-host
for t in rsa ed25519; do
  [ -f "/root/.ssh-host/ssh_host_${t}_key" ] || ssh-keygen -q -t "$t" -N '' -f "/root/.ssh-host/ssh_host_${t}_key"
  cp -f "/root/.ssh-host/ssh_host_${t}_key" "/root/.ssh-host/ssh_host_${t}_key.pub" /etc/ssh/
  chmod 600 "/etc/ssh/ssh_host_${t}_key"
done

# Root login: password from ROOT_PASSWORD, optional keys from AUTHORIZED_KEYS.
[ -n "${ROOT_PASSWORD:-}" ] && echo "root:${ROOT_PASSWORD}" | chpasswd
[ -n "${AUTHORIZED_KEYS:-}" ] && printf '%s\n' "$AUTHORIZED_KEYS" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
cat > /etc/ssh/sshd_config.d/railway.conf <<CFG
Port 22
ListenAddress 0.0.0.0
ListenAddress ::
PermitRootLogin yes
PasswordAuthentication $([ -n "${ROOT_PASSWORD:-}" ] && echo yes || echo no)
ClientAliveInterval 60
CFG
/usr/sbin/sshd

# sshd strips the environment: hand provider keys, tokens and the server login to SSH
# sessions too (so `oc` can attach to the running server). %q quotes any value safely.
for v in $(compgen -e | grep -E '_API_KEY$|^OPENCODE_|^(GH_TOKEN|GITHUB_TOKEN|TZ|PORT)$'); do
  printf 'export %s=%q\n' "$v" "${!v}"
done > /etc/profile.d/railway-env.sh

# git push over https with GH_TOKEN, no interactive login.
[ -n "${GH_TOKEN:-}" ] && gh auth setup-git >/dev/null 2>&1 || true

# nginx on $PORT: /healthcheck answers only once opencode itself does; everything else
# goes to opencode, which does its own basic auth. SSE + PTY websockets: no buffering.
AUTH=$(printf '%s:%s' "$OPENCODE_SERVER_USERNAME" "$OPENCODE_SERVER_PASSWORD" | base64 -w0)
cat > /etc/nginx/sites-enabled/default <<CFG
server {
  listen ${PORT} default_server;
  listen [::]:${PORT} default_server;
  client_max_body_size 100m;
  location = /healthcheck {
    proxy_pass http://127.0.0.1:4096/global/health;
    proxy_set_header Authorization "Basic ${AUTH}";
  }
  location / {
    proxy_pass http://127.0.0.1:4096;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$http_connection;
    proxy_set_header Host \$host;
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 1d;
    proxy_send_timeout 1d;
  }
}
CFG
nginx

# Railway counts the kernel's cache of files this container has touched as the
# service's memory, and with no memory pressure it is never freed: one npm
# install shows as hundreds of MB. Drop it for the home volume every 15 min.
( while sleep 900; do nice -n 19 drop-file-cache /root /tmp || true; done ) &

echo "== opencode box ready: web UI on :${PORT} (user ${OPENCODE_SERVER_USERNAME}), sshd on :22, opencode $(opencode --version)"
cd /root/workspace
exec opencode web --hostname 127.0.0.1 --port 4096
