#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  printf 'Run this artifact installer as root.\n' >&2
  exit 1
fi

printf '[Guidance] Planting inert incident-response artifacts...\n'
install -d -m 0755 /opt/ihpl-training /usr/local/libexec /usr/local/share
install -m 0644 "$(dirname -- "${BASH_SOURCE[0]}")/maintenance.php" /var/www/plinkcom/public/assets/.maintenance.php

if ! id telemetry-sync >/dev/null 2>&1; then
  useradd --system --create-home --shell /usr/sbin/nologin telemetry-sync
fi
passwd -l telemetry-sync >/dev/null 2>&1 || true
printf 'telemetry-sync ALL=(root) NOPASSWD: /usr/bin/id\n' > /etc/sudoers.d/telemetry-sync
chmod 0440 /etc/sudoers.d/telemetry-sync
visudo --check --file=/etc/sudoers.d/telemetry-sync

cat > /tmp/plinko-update-check.c <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
int main(void) {
    uid_t user = getuid();
    gid_t group = getgid();
    if (setresgid(group, group, group) != 0 || setresuid(user, user, user) != 0) return 1;
    puts("IHPL diagnostics: training artifact only; privileges dropped.");
    return 0;
}
EOF
gcc -O2 -Wall -Wextra -o /usr/local/libexec/plinko-update-check /tmp/plinko-update-check.c
rm -f /tmp/plinko-update-check.c
chown root:root /usr/local/libexec/plinko-update-check
chmod 4755 /usr/local/libexec/plinko-update-check

install -m 0755 /usr/bin/sleep /opt/ihpl-training/bishop-agent
cat > /etc/systemd/system/plinko-telemetry-agent.service <<'EOF'
[Unit]
Description=Legacy Plinko telemetry compatibility agent
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/opt/ihpl-training/bishop-agent infinity
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /opt/ihpl-training/banner_listener.py <<'PY'
#!/usr/bin/env python3
import socket

with socket.socket() as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 4444))
    server.listen(4)
    while True:
        client, _ = server.accept()
        with client:
            client.sendall(b"IHPL inert training listener; command execution disabled.\n")
PY
chmod 0755 /opt/ihpl-training/banner_listener.py
cat > /etc/systemd/system/plinko-maintenance-listener.service <<'EOF'
[Unit]
Description=PlinkCom legacy maintenance listener
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/usr/bin/python3 /opt/ihpl-training/banner_listener.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/plinko-health-refresh.service <<'EOF'
[Unit]
Description=Refresh legacy PlinkCom health marker

[Service]
Type=oneshot
ExecStart=/usr/bin/touch /var/tmp/.plinkcom-health
EOF
cat > /etc/systemd/system/plinko-health-refresh.timer <<'EOF'
[Unit]
Description=Refresh legacy PlinkCom health marker every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Unit=plinko-health-refresh.service

[Install]
WantedBy=timers.target
EOF

printf '# training clue only; this is deliberately not /etc/ld.so.preload\n/usr/local/lib/libhorsehide.so\n' > /etc/ld.so.preload.training
printf 'bishop-agent\nplinko-maintenance-listener\n' > /usr/local/share/.process-hide.training
chmod 0644 /etc/ld.so.preload.training /usr/local/share/.process-hide.training

systemctl daemon-reload
systemctl enable --now plinko-telemetry-agent.service plinko-maintenance-listener.service plinko-health-refresh.timer
printf '[Guidance] Inert artifacts installed; no command shell or C2 behavior is present.\n'
