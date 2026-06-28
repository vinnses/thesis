#!/usr/bin/env bash
set -euo pipefail

user="${TEXUSER:-${USERNAME:-$(id -un)}}"
home_dir="$(getent passwd "$user" | cut -d: -f6)"

sudo ssh-keygen -A >/dev/null
sudo install -d -m 0700 -o "$user" -g "$user" "$home_dir/.ssh"
if [ -s /run/secrets/authorized_keys ]; then
  sudo install -m 0600 -o "$user" -g "$user" \
    /run/secrets/authorized_keys "$home_dir/.ssh/authorized_keys"
fi
sudo install -d -m 0755 /run/sshd
sudo tee /etc/ssh/sshd_config.d/workspace.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
sudo /usr/sbin/sshd -t
pgrep -x sshd >/dev/null || sudo /usr/sbin/sshd

case "${JUPYTER_ENABLED:-1}" in
  1|true|yes|on) ;;
  *) exit 0 ;;
esac

state_dir="$home_dir/.local/state/jupyterlab"
settings_dir="$home_dir/.jupyter/lab/user-settings/@jupyterlab/apputils-extension"
mkdir -p "$state_dir" "$settings_dir"
cat > "$settings_dir/themes.jupyterlab-settings" <<'EOF'
{
  "theme": "JupyterLab Dark"
}
EOF

if [ -s "$state_dir/jupyterlab.pid" ] && kill -0 "$(cat "$state_dir/jupyterlab.pid")" 2>/dev/null; then
  exit 0
fi

args=(
  lab --ip=0.0.0.0 --port="${JUPYTER_PORT:-8888}" --no-browser
  --ServerApp.root_dir=/workspace
  --ServerApp.terminado_settings='{"shell_command":["/bin/bash","-l"]}'
)
if [ -n "${JUPYTER_TOKEN:-}" ]; then
  args+=(--IdentityProvider.token="${JUPYTER_TOKEN}")
fi

nohup /opt/jupyter/bin/jupyter "${args[@]}" >"$state_dir/jupyterlab.log" 2>&1 &
echo "$!" > "$state_dir/jupyterlab.pid"
