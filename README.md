# Friday Horse Plinko Scrimmage

This repository builds a four-host, self-contained blue-team practice range inspired by the HPCC4 onboarding packet. It recreates the required services, visual identity, and functional host findings such as unauthorized accounts, weak permissions, scheduled persistence, listeners, and excessive application access. Payload-class findings are explicitly identified as non-executing stand-ins and do not contact command-and-control infrastructure.

## Topology

| Host | Reference OS | Critical services |
| --- | --- | --- |
| `guidance` | Ubuntu 22.04 | SSH, PlinkCom (Apache/PHP) |
| `ignition` | Fedora Server 38 | SSH, Open WebUI v0.11.3 |
| `assembly` | Windows Server 2022 | RDP, Jenkins |
| `manifest` | Windows Server 2019 | RDP, MariaDB |

Change the addresses through each setup script's parameters. The scripts do not configure a static interface because interface names and gateways vary by hypervisor.

```text
                           Blue-team subnet

  browser ───────► guidance:80 ───────► MariaDB (local or manifest:3306)
                       │                           ▲
  SSH ───────────► guidance:22                     │
  browser ───────► ignition:80                     │
  SSH ───────────► ignition:22                     │
  browser ───────► assembly:8080 ──────────────────┘
  RDP ───────────► assembly:3389 / manifest:3389
```

## Build order

Run the scripts from an elevated local console in this order:

1. Copy this repository to each VM (or mount a read-only deployment share).
2. If using remote MariaDB, run `manifest/Setup-Manifest.ps1` on Manifest in an elevated Windows PowerShell session.
3. On Guidance, run `sudo guidance/setup.sh` with either `--manifest-ip IP` or `--local-mariadb`.
4. On Ignition, run `sudo ignition/setup.sh`.
5. On Assembly, run `assembly/Setup-Assembly.ps1` in an elevated Windows PowerShell session.
6. Change all starter passwords and update the service configuration together.

Example commands are in each host's README. Setup logs are written beneath `/var/log/ihpl-setup` on Linux and `C:\ProgramData\IHPL\Logs` on Windows.

## Credentials

The packet's starter password is used by default so the range is usable immediately:

- OS administrator: `plinktern` / `H00ves0nTheM00n`
- Scoring OS account: `jmoney` / `H00ves0nTheM00n`
- PlinkCom administrator: `plinktern` / `H00ves0nTheM00n`
- Open WebUI administrator: `plinktern@plinko.horse` / `H00ves0nTheM00n`
- Jenkins administrator: `plinktern` / `H00ves0nTheM00n`
- MariaDB administrator: `plinktern` / `H00ves0nTheM00n`

Each service also has a `jmoney` scoring account with the same starter password.

Override these values at install time and rotate them before exposing the range to participants. See [BLUE_TEAM.md](BLUE_TEAM.md) for the participant handout and [ANSWER_KEY.md](ANSWER_KEY.md) for organizer-only findings.

## Range behavior

Account, authorization, ACL, service, timer, cron, and scheduled-task findings are installed as functional configurations. The Sliver and IMIX process indicators remain disconnected from C2. The PHP web-shell, command-shell listener, rootkit, malicious SUID behavior, and Jenkins RCE findings are non-executing stand-ins: they preserve discovery and remediation exercises without accepting operator commands or installing exploit code. The organizer answer key identifies the behavior of every finding.

## Validation

From the repository root:

```bash
bash tests/validate.sh
```

The check parses both Linux setup scripts, verifies the required project structure and service definitions, and checks that high-risk shell patterns are absent. Full integration requires the four reference operating systems.

With Docker available, `bash tests/smoke-plinkcom.sh` starts disposable MariaDB and PHP containers, signs in as `jmoney`, loads the dashboard, and checks the status API.
