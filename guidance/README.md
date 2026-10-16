# Guidance — PlinkCom

Guidance is an Ubuntu 22.04 host running OpenSSH, Apache, PHP, and the custom PlinkCom dashboard. PlinkCom reads launch data from MariaDB, either locally or from Manifest over TCP 3306.

## Install

Copy the `guidance` directory to the VM, then choose one database mode.

Use MariaDB on Manifest:

```bash
sudo ./setup.sh \
  --manifest-ip 172.16.1.40 \
  --password 'H00ves0nTheM00n'
```

Or install MariaDB locally on Guidance, bound only to loopback:

```bash
sudo ./setup.sh \
  --local-mariadb \
  --password 'H00ves0nTheM00n'
```

Supported options:

- `--manifest-ip`: connect PlinkCom to MariaDB at the supplied address.
- `--local-mariadb`: install MariaDB locally, bind it to `127.0.0.1`, and seed the `plinkcom` database.
- `--password`: starter OS/PlinkCom/MariaDB password.
- `--skip-training-artifacts`: install only the scored services.

Exactly one of `--manifest-ip` or `--local-mariadb` is required. The script is idempotent. It does not assign an interface address or enable UFW globally. If UFW is already active, it adds SSH/HTTP ingress and, in remote mode, narrowly scoped MariaDB egress without changing the default policy.

When using Manifest, its installer creates the remote `jmoney` account with the MariaDB host pattern `%` and opens TCP 3306 from any source address.

## Verification

```bash
systemctl --no-pager status ssh apache2
# Include mariadb when using --local-mariadb:
systemctl --no-pager status mariadb
curl -fsS http://127.0.0.1/api/status.php
id jmoney
id plinktern
MANIFEST_IP=172.16.1.40
mysql -h "$MANIFEST_IP" -u jmoney -p -e 'SELECT status FROM plinkcom.rockets;'
# For --local-mariadb, use: mysql -h 127.0.0.1 -u jmoney -p
```

Browse to Guidance and sign in as `plinktern` for administration or `jmoney` for scoring. Both OS accounts initially use `H00ves0nTheM00n`; `plinktern` belongs to `sudo` and `jmoney` does not.

The PlinkCom sidebar provides Dashboard, My Rocket, Cargo, Mission Logs, Crew Manifest, Attachments, and Profile. The Profile page lets the signed-in operator change their application username and password after confirming their current password. The range intentionally installs one direct web vulnerability on each operational page: missing update authorization, command injection, local file inclusion, SQL injection, and unrestricted executable upload. See the organizer-only answer key for proof and remediation steps.

## Dependency change

When rotating the `jmoney` MariaDB password, update `PLINKCOM_DB_PASSWORD` in `/etc/apache2/conf-available/plinkcom-runtime.conf`, reload Apache, and test the dashboard before ending the maintenance window.
