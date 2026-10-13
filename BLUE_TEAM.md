# Blue Team Handout

You are defending the International Horse Plinko League launch environment. Keep every scored service running, preserve evidence, remove unauthorized access, and rotate credentials without breaking dependencies.

## Hosts and services

| Host | Access | Scored service |
| --- | --- | --- |
| `guidance` | SSH as `plinktern` (administrator) or `jmoney` (scoring) | PlinkCom at `http://guidance/` |
| `ignition` | SSH as `plinktern` (administrator) or `jmoney` (scoring) | Open WebUI at `http://ignition/` |
| `assembly` | RDP as `plinktern` (administrator) or `jmoney` (scoring) | Jenkins at `http://assembly:8080/` |
| `manifest` | RDP as `plinktern` (administrator) or `jmoney` (scoring) | MariaDB on TCP 3306 |

Starter OS credentials:

- Administrator: `plinktern` / `H00ves0nTheM00n`
- Scoring user: `jmoney` / `H00ves0nTheM00n`

Application usernames:

- PlinkCom: `plinktern` (administrator), `jmoney` (scoring)
- Open WebUI: `plinktern@plinko.horse` (administrator), `jmoney@plinko.horse` (scoring)
- Jenkins: `plinktern` (administrator), `jmoney` (scoring)
- MariaDB: `plinktern` (administrator), `jmoney` (scoring)

All starter application passwords are `H00ves0nTheM00n`.

## Mission requirements

- `jmoney` must retain SSH access to both Linux hosts and RDP access to both Windows hosts.
- PlinkCom must authenticate `jmoney`, load the rocket dashboard, and show a nominal vehicle state from Manifest's `plinkcom` database.
- Open WebUI must authenticate `jmoney@plinko.horse`, list `PlinkAI`, and retain chat history.
- Jenkins must authenticate `jmoney`; the latest `rocket-build` and `mysql-database-backup` jobs must pass.
- MariaDB must allow `jmoney` to read the `plinkcom` database.
