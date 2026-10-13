# Friday Horse Plinko Scrimmage

This repository builds a four-host, self-contained blue-team practice range inspired by the HPCC4 onboarding packet. It recreates the required services and visual identity while keeping the planted incident artifacts inert: none of the simulations opens an interactive shell, executes operator-supplied commands, contacts a command-and-control server, or installs a kernel rootkit.

## Topology

| Host | Reference OS | Default address | Critical services |
| --- | --- | --- | --- |
| `guidance` | Ubuntu Server 22.04 | `172.16.1.10` | SSH, PlinkCom (Apache/PHP) |
| `ignition` | Fedora Server 38 | `172.16.1.20` | SSH, Open WebUI v0.11.3 |
| `assembly` | Windows Server 2022 | `172.16.1.30` | RDP, Jenkins |
| `manifest` | Windows Server 2019 | `172.16.1.40` | RDP, MariaDB |

Change the addresses through each setup script's parameters. The scripts do not configure a static interface because interface names and gateways vary by hypervisor.

```text
                           Blue-team subnet

  browser ───────► guidance:80 ─────────────► manifest:3306
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
2. On Manifest, run `manifest/Setup-Manifest.ps1` in an elevated Windows PowerShell session.
3. On Guidance, run `sudo guidance/setup.sh` and pass Manifest's actual IP.
4. On Ignition, run `sudo ignition/setup.sh`.
5. On Assembly, run `assembly/Setup-Assembly.ps1` in an elevated Windows PowerShell session.
6. Change all starter passwords and update the service configuration together.

Example commands are in each host's README. Setup logs are written beneath `/var/log/ihpl-setup` on Linux and `C:\ProgramData\IHPL\Logs` on Windows.

## Credentials

The packet's starter credential is used by default so the range is usable immediately:

- OS administrator: `plinktern` / `H00ves0nTheM00n`
- Scoring OS account: `jmoney` / `H00ves0nTheM00n`
- PlinkCom: `jmoney` / `H00ves0nTheM00n`
- Open WebUI: `jmoney@plinko.horse` / `H00ves0nTheM00n`
- Jenkins: `jmoney` / `H00ves0nTheM00n`
- MariaDB: `jmoney` / `H00ves0nTheM00n`

Override these values at install time and rotate them before exposing the range to participants. See [BLUE_TEAM.md](BLUE_TEAM.md) for the participant handout and [ANSWER_KEY.md](ANSWER_KEY.md) for organizer-only findings.

## Safety boundary

The packet requested real implants, reverse/bind shells, a rootkit, a PHP command shell, and a working Jenkins RCE. This project substitutes forensic simulations that create the same kinds of observable clues without command execution or C2 traffic. The web-shell page returns a fixed training response; beacon processes only sleep or append to local logs; shell simulations accept a connection only on loopback and return a banner; suspicious accounts are locked or narrowly constrained. Do not replace these with operational malware on a shared network.

## Validation

From the repository root:

```bash
bash tests/validate.sh
```

The check parses both Linux setup scripts, verifies the required project structure and service definitions, and checks that high-risk shell patterns are absent. Full integration requires the four reference operating systems.

With Docker available, `bash tests/smoke-plinkcom.sh` starts disposable MariaDB and PHP containers, signs in as `jmoney`, loads the dashboard, and checks the status API.
