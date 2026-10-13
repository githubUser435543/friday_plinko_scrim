# Organizer Answer Key

Keep this file away from participants. Account, authorization, ACL, service, timer, cron, listener, and scheduled-task findings are functional configurations. Rows explicitly labeled as non-executing or disconnected are payload stand-ins. The expected workflow is identify, preserve, contain, remove, and verify the scored service.

## Guidance

| Finding | How to find it | Installed behavior | Remediation |
| --- | --- | --- | --- |
| Maintenance PHP artifact | `find /var/www/plinkcom -type f -name '*.php' -mtime -30`; inspect `public/assets/.maintenance.php` | Non-executing PHP web-shell stand-in; returns a fixed HTTP 403 response | Preserve/hash, remove the file, review Apache access logs, redeploy from this repository |
| `telemetry-sync` account | `getent passwd`; `sudo -l -U telemetry-sync` | Real locked service account with a live sudoers rule limited to `/usr/bin/id` | Remove `/etc/sudoers.d/telemetry-sync`, lock/remove the account |
| `plinko-update-check` | `find / -xdev -perm -4000 -type f 2>/dev/null` | Real mode-4755 diagnostic; non-executing privilege-escalation stand-in that drops privileges immediately | Capture hash, remove `/usr/local/libexec/plinko-update-check` |
| `bishop-agent` process | `grep --no-messages bishop /proc/*/exe`; inspect `systemctl status plinko-telemetry-agent` | Running Sliver-like process indicator disconnected from C2 | Stop/disable `plinko-telemetry-agent.service`, remove its unit and executable |
| Loopback listener | `ss -lntp`; inspect `plinko-maintenance-listener` | Live TCP listener on loopback that returns a fixed banner and does not execute commands | Stop/disable the service and remove `/opt/ihpl-training/banner_listener.py` |
| Persistence timer | `systemctl list-timers --all`; inspect `plinko-health-refresh.*` | Active systemd timer that refreshes a hidden marker every minute | Disable/remove both units and delete the local heartbeat marker |
| Rootkit clues | `find /etc /usr/local -iname '*preload*' -o -iname '*hide*'` | Non-loaded rootkit configuration stand-ins; the real `/etc/ld.so.preload` is not changed | Remove `/etc/ld.so.preload.training` and `/usr/local/share/.process-hide.training`; verify the real `/etc/ld.so.preload` is absent/legitimate |

After cleanup, verify `sshd`, Apache, PlinkCom login, the dashboard API, and MariaDB connectivity.

## Ignition

| Finding | How to find it | Installed behavior | Remediation |
| --- | --- | --- | --- |
| `support.bot@plinko.horse` | Open WebUI admin panel or its Users API | Live unauthorized Open WebUI account | Delete/disable the account and review chats/tokens |
| `flight-cache` account | `getent passwd`; inspect `/etc/sudoers.d/flight-cache` | Real locked service account with a live sudoers rule limited to `/usr/bin/id` | Remove its sudo rule, lock/remove account |
| `launch-diagnostics` | `find / -xdev -perm -4000 -type f 2>/dev/null` | Real mode-4755 diagnostic; non-executing privilege-escalation stand-in that drops privileges immediately | Hash and remove `/usr/local/libexec/launch-diagnostics` |
| `telemetry-indexer` process | `systemctl status telemetry-indexer`; inspect `/proc/*/exe` | Running IMIX-like process indicator disconnected from C2 | Disable/remove the service and `/opt/ihpl-training/telemetry-indexer` |
| Root cron entry | Inspect `/etc/cron.d/telemetry-index-refresh` | Active root cron job that refreshes a hidden heartbeat every minute | Remove `/etc/cron.d/telemetry-index-refresh` |
| Downloads artifact | `find /home -path '*/Downloads/*' -ls` | Executable, non-command backdoor stand-in in a user staging location | Preserve/hash and remove `telemetry_viewer`; review shell history |
| Suspicious environment file | `find /etc -type f -mtime -30`; inspect `/etc/profile.d/telemetry-debug.sh` | Active environment persistence applied to new login sessions | Remove the file and start fresh sessions |

Verify SSH, the `open-webui` container, the local `plinkai-stub` service, login as `jmoney@plinko.horse`, and a short PlinkAI chat.

## Assembly

| Finding | How to find it | Installed behavior | Remediation |
| --- | --- | --- | --- |
| `buildsvc` and `former.intern` | Jenkins **Manage Users**; inspect `init.groovy.d` | Live unauthorized Jenkins users | Preserve then remove `10-ihpl-bootstrap.groovy`, delete both users, rotate tokens/passwords, inspect builds |
| Anonymous read | Jenkins security settings or unauthenticated GET | Live excessive authorization setting | Disable anonymous read and adopt role/matrix authorization |
| Writable staging folder | `Get-Acl C:\ProgramData\IHPL\Staging` | Live `Users:Modify` ACL | Remove `Users:Modify`; grant only Jenkins service and administrators |
| Scheduled inventory task | `Get-ScheduledTask -TaskPath '\IHPL\'` | Active startup task running as SYSTEM | Export for evidence, unregister `IHPL Build Inventory` |
| Version-risk marker | Jenkins system information and `C:\ProgramData\IHPL\Training\jenkins-version-review.txt` | Pinned Jenkins version and live patch-management finding; no RCE exploit code is installed | Upgrade Jenkins/plugins from official sources and retest jobs |

Validate both job results, Jenkins login, RDP, and connectivity from Assembly to Manifest TCP 3306.

## Manifest

| Finding | How to find it | Installed behavior | Remediation |
| --- | --- | --- | --- |
| `telemetry_admin@localhost` | `SELECT User,Host,account_locked FROM mysql.user;` | Live unauthorized MariaDB administrator with global privileges | Revoke, drop the account, rotate affected credentials, review MariaDB logs |
| Loopback TCP 4444 | `Get-NetTCPConnection -State Listen`; inspect owning process/task | Live SYSTEM-owned loopback listener that returns a fixed banner and does not execute commands | Stop and unregister `IHPL Local Diagnostics`; remove the script |
| `manifest-indexer` heartbeat | `Get-ScheduledTask -TaskPath '\IHPL\'`; inspect training logs | Active scheduled heartbeat serving as a disconnected IMIX-like process/persistence indicator | Unregister task and remove its script/logs |
| `win-update-helper.exe.training` | Search `C:\ProgramData\IHPL\Training` and startup paths | Non-executing Sliver-like implant marker disconnected from C2 | Preserve/hash, delete marker and any startup reference |
| `dbmaint` local user | Enumerate local accounts through Computer Management or the WinNT provider; inspect Administrators membership | Real disabled local account retained in the Administrators group | Remove account and rotate credentials |
| Broad data ACL | `Get-Acl C:\ProgramData\MariaDB\data` | Live read/execute access for built-in Users across the MariaDB data tree | Remove `Users` access; retain SYSTEM, Administrators, and MariaDB service identity |

Verify RDP, MariaDB service state, firewall scope, application access from Guidance, and both `jmoney` and PlinkCom read paths after cleanup.
