#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  printf 'Run this artifact installer as root.\n' >&2
  exit 1
fi

printf '[Ignition] Planting inert incident-response artifacts...\n'
install -d -m 0755 /opt/ihpl-training /usr/local/libexec /home/jmoney/Downloads

if ! id flight-cache >/dev/null 2>&1; then
  useradd --system --create-home --shell /sbin/nologin flight-cache
fi
passwd -l flight-cache >/dev/null 2>&1 || true
printf 'flight-cache ALL=(root) NOPASSWD: /usr/bin/id\n' > /etc/sudoers.d/flight-cache
chmod 0440 /etc/sudoers.d/flight-cache
visudo --check --file=/etc/sudoers.d/flight-cache

cat > /tmp/launch-diagnostics.c <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
int main(void) {
    uid_t user = getuid();
    gid_t group = getgid();
    if (setresgid(group, group, group) != 0 || setresuid(user, user, user) != 0) return 1;
    puts("Launch diagnostics training sample; privileges dropped.");
    return 0;
}
EOF
gcc -O2 -Wall -Wextra -o /usr/local/libexec/launch-diagnostics /tmp/launch-diagnostics.c
rm -f /tmp/launch-diagnostics.c
chown root:root /usr/local/libexec/launch-diagnostics
chmod 4755 /usr/local/libexec/launch-diagnostics

install -m 0755 /usr/bin/sleep /opt/ihpl-training/telemetry-indexer
cat > /etc/systemd/system/telemetry-indexer.service <<'EOF'
[Unit]
Description=Legacy telemetry indexing compatibility service
After=network.target

[Service]
Type=simple
User=nobody
ExecStart=/opt/ihpl-training/telemetry-indexer infinity
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/cron.d/telemetry-index-refresh <<'EOF'
* * * * * root /usr/bin/touch /var/tmp/.telemetry-index-heartbeat
EOF
chmod 0644 /etc/cron.d/telemetry-index-refresh

cat > /home/jmoney/Downloads/telemetry_viewer <<'EOF'
#!/usr/bin/env bash
printf 'IHPL training artifact: remote access functions are disabled.\n'
EOF
chown -R jmoney:jmoney /home/jmoney/Downloads
chmod 0755 /home/jmoney/Downloads/telemetry_viewer

cat > /etc/profile.d/telemetry-debug.sh <<'EOF'
# Suspicious but inert training clue.
export IHPL_TELEMETRY_DEBUG=1
EOF
chmod 0644 /etc/profile.d/telemetry-debug.sh

systemctl daemon-reload
systemctl enable --now telemetry-indexer.service
printf '[Ignition] Inert artifacts installed; no command shell or C2 behavior is present.\n'
