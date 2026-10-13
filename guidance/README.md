# Guidance — PlinkCom

Guidance is an Ubuntu 22.04 host running OpenSSH, Apache, PHP, and the custom PlinkCom dashboard. PlinkCom reads launch data from Manifest over MariaDB TCP 3306.

## Install

Copy the `guidance` directory to the VM, then run:

```bash
sudo ./setup.sh \
  --manifest-ip 172.16.1.40 \
  --guidance-ip 172.16.1.10 \
  --password 'H00ves0nTheM00n'
```

Supported options:

- `--manifest-ip`: MariaDB host. Required unless the default is correct.
- `--guidance-ip`: this host's address, used in documentation and UFW rules.
- `--password`: starter OS/PlinkCom/MariaDB password.
- `--skip-training-artifacts`: install only the scored services.

The script is idempotent. It does not assign an interface address or enable UFW globally. If UFW is already active, it adds SSH/HTTP ingress and MariaDB egress rules without changing the default policy.

## Verification

```bash
systemctl --no-pager status ssh apache2
curl -fsS http://127.0.0.1/api/status.php
mysql -h 172.16.1.40 -u jmoney -p -e 'SELECT status FROM plinkcom.rockets;'
```

Browse to Guidance and sign in as `plinktern` for administration or `jmoney` for scoring. Both accounts initially use `H00ves0nTheM00n`.

## Dependency change

When rotating the `jmoney` MariaDB password on Manifest, update `PLINKCOM_DB_PASSWORD` in `/etc/apache2/conf-available/plinkcom-runtime.conf`, reload Apache, and test the dashboard before ending the maintenance window.
