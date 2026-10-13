# Blue Team Handout

You are defending the International Horse Plinko League launch environment. Keep every scored service running, preserve evidence, remove unauthorized access, and rotate credentials without breaking dependencies.

## Hosts and services

| Host | Default IP | Access | Scored service |
| --- | --- | --- | --- |
| `guidance` | `172.16.1.10` | SSH as `jmoney` | PlinkCom at `http://172.16.1.10/` |
| `ignition` | `172.16.1.20` | SSH as `jmoney` | Open WebUI at `http://172.16.1.20/` |
| `assembly` | `172.16.1.30` | RDP as `jmoney` | Jenkins at `http://172.16.1.30:8080/` |
| `manifest` | `172.16.1.40` | RDP as `jmoney` | MariaDB on TCP 3306 |

Starter password: `H00ves0nTheM00n`

Application usernames:

- PlinkCom: `jmoney`
- Open WebUI: `jmoney@plinko.horse`
- Jenkins: `jmoney`
- MariaDB: `jmoney`

## Mission requirements

- `jmoney` must retain SSH access to both Linux hosts and RDP access to both Windows hosts.
- PlinkCom must authenticate `jmoney`, load the rocket dashboard, and show a nominal vehicle state from Manifest's `plinkcom` database.
- Open WebUI must authenticate `jmoney@plinko.horse`, list `PlinkAI`, and retain chat history.
- Jenkins must authenticate `jmoney`; the latest `rocket-build` and `mysql-database-backup` jobs must pass.
- MariaDB must allow `jmoney` to read the `plinkcom` database.

## First-response checklist

1. Record service state and current network listeners before changing anything.
2. Inventory local accounts, service accounts, administrators/sudoers, scheduled tasks, timers, and cron jobs.
3. Inspect web roots, service configuration, startup locations, and recently changed files.
4. Rotate OS and application credentials one dependency at a time. Test after every change.
5. Restrict MariaDB ingress to Guidance and approved scoring/admin sources on TCP 3306.
6. Preserve suspicious files and hashes in a quarantine directory before removal.
7. Confirm the five mission requirements after remediation.

The range contains deliberate findings. Some are inert forensic simulations rather than live malware, but they should still be investigated and removed as if they were unauthorized production artifacts.
