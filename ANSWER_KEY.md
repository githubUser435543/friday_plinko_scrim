# Organizer Answer Key

Keep this file away from participants. All planted artifacts are intentionally inert. The expected workflow is identify, preserve, contain, remove, and verify the scored service.

## Guidance

| Finding | How to find it | What it simulates | Remediation |
| --- | --- | --- | --- |
| Maintenance PHP artifact | `find /var/www/plinkcom -type f -name '*.php' -mtime -30`; inspect `public/assets/.maintenance.php` | PHP web shell | Preserve/hash, remove the file, review Apache access logs, redeploy from this repository |
| `telemetry-sync` account | `getent passwd`; `sudo -l -U telemetry-sync` | Unauthorized sudo account | Remove `/etc/sudoers.d/telemetry-sync`, lock/remove the account |
| `plinko-update-check` | `find / -xdev -perm -4000 -type f 2>/dev/null` | Suspicious setuid executable | Capture hash, remove `/usr/local/libexec/plinko-update-check` |
| `bishop-agent` process | `grep --no-messages bishop /proc/*/exe`; inspect `systemctl status plinko-telemetry-agent` | Sliver-like process indicator | Stop/disable `plinko-telemetry-agent.service`, remove its unit and executable |
| Loopback listener | `ss -lntp`; inspect `plinko-maintenance-listener` | Netcat/bind-shell listener | Stop/disable the service and remove `/opt/ihpl-training/banner_listener.py` |
| Persistence timer | `systemctl list-timers --all`; inspect `plinko-health-refresh.*` | `at`/scheduled persistence | Disable/remove both units and delete the local heartbeat log |
| Rootkit clues | `find /etc /usr/local -iname '*preload*' -o -iname '*hide*'` | Userland rootkit configuration | Remove `/etc/ld.so.preload.training` and `/usr/local/share/.process-hide.training`; verify the real `/etc/ld.so.preload` is absent/legitimate |

After cleanup, verify `sshd`, Apache, PlinkCom login, the dashboard API, and MariaDB connectivity. The SUID sample drops privileges immediately and accepts no input; the listener only returns a fixed banner.

## Ignition

| Finding | How to find it | What it simulates | Remediation |
| --- | --- | --- | --- |
| `support.bot@plinko.horse` | Open WebUI admin panel or its Users API | Unauthorized Open WebUI user | Delete/disable the account and review chats/tokens |
| `flight-cache` account | `getent passwd`; inspect `/etc/sudoers.d/flight-cache` | Unauthorized sudo user | Remove its sudo rule, lock/remove account |
| `launch-diagnostics` | `find / -xdev -perm -4000 -type f 2>/dev/null` | Malicious SUID utility | Hash and remove `/usr/local/libexec/launch-diagnostics` |
| `telemetry-indexer` process | `systemctl status telemetry-indexer`; inspect `/proc/*/exe` | Imix-like beacon | Disable/remove the service and `/opt/ihpl-training/telemetry-indexer` |
| Root cron entry | `sudo crontab -l`; inspect `/etc/cron.d` | Beacon revival | Remove `/etc/cron.d/telemetry-index-refresh` |
| Downloads artifact | `find /home -path '*/Downloads/*' -ls` | User-staged backdoor | Preserve/hash and remove `telemetry_viewer`; review shell history |
| Suspicious environment file | `find /etc -type f -mtime -30`; inspect `/etc/profile.d/telemetry-debug.sh` | Environment persistence | Remove the file and start fresh sessions |

Verify SSH, the `open-webui` container, the local `plinkai-stub` service, login as `jmoney@plinko.horse`, and a short PlinkAI chat.

## Assembly

| Finding | How to find it | What it simulates | Remediation |
| --- | --- | --- | --- |
| `buildsvc` and `former.intern` | Jenkins **Manage Users**; inspect `init.groovy.d` | Unauthorized Jenkins users | Preserve then remove `10-ihpl-bootstrap.groovy`, delete both users, rotate tokens/passwords, inspect builds |
| Anonymous read | Jenkins security settings or unauthenticated GET | Excessive authorization | Disable anonymous read and adopt role/matrix authorization |
| Writable staging folder | `Get-Acl C:\ProgramData\IHPL\Staging` | Weak file permissions | Remove `Users:Modify`; grant only Jenkins service and administrators |
| Scheduled inventory task | `Get-ScheduledTask -TaskPath '\IHPL\'` | Persistence | Export for evidence, unregister `IHPL Build Inventory` |
| Version-risk marker | Jenkins system information and `C:\ProgramData\IHPL\Training\jenkins-version-review.txt` | Patch-management finding | Upgrade Jenkins/plugins from official sources and retest jobs |

No RCE exploit is included. Validate both job results, Jenkins login, RDP, and connectivity from Assembly to Manifest TCP 3306.

## Manifest

| Finding | How to find it | What it simulates | Remediation |
| --- | --- | --- | --- |
| `telemetry_admin@localhost` | `SELECT User,Host,account_locked FROM mysql.user;` | Unauthorized database administrator | Revoke, drop the account, rotate affected credentials, review MariaDB logs |
| Loopback TCP 4444 | `Get-NetTCPConnection -State Listen`; inspect owning process/task | Bind shell / `nc.exe -e cmd` | Stop and unregister `IHPL Local Diagnostics`; remove the script |
| `manifest-indexer` heartbeat | `Get-ScheduledTask -TaskPath '\IHPL\'`; inspect training logs | Imix-like beacon/persistence | Unregister task and remove its script/logs |
| `win-update-helper.exe.training` | Search `C:\ProgramData\IHPL\Training` and startup paths | Sliver-like implant | Preserve/hash, delete marker and any startup reference |
| `dbmaint` local user | `Get-LocalUser`; `Get-LocalGroupMember Administrators` | Unauthorized Windows account | Disable/remove account and rotate credentials |
| Broad data ACL | `Get-Acl C:\ProgramData\MariaDB\data` | Weak database file permissions | Remove `Users` access; retain SYSTEM, Administrators, and MariaDB service identity |

The listener accepts only loopback connections, sends a fixed warning, and closes; it cannot execute commands. Verify RDP, MariaDB service state, firewall scope, application access from Guidance, and both `jmoney` and PlinkCom read paths after cleanup.
