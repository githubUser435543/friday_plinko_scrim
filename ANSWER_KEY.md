# Organizer Answer Key

Keep this file away from participants. The planted accounts, authorization flaws, command paths, listeners, persistence, and privilege-escalation findings are functional. Only the rows explicitly identified as Sliver or IMIX indicators are disconnected from C2. The expected workflow is identify, preserve, contain, remove, and verify the scored service.

## Guidance

| Finding | How to find it | Installed behavior | Remediation |
| --- | --- | --- | --- |
| Maintenance PHP web shell | `find /var/www/plinkcom -type f -name '*.php' -mtime -30`; inspect `public/.maintenance.php` | Web-accessible command shell accepting the `cmd` request parameter | Preserve/hash, remove the file, review Apache access logs, redeploy from this repository |
| `telemetry-sync` account | `getent passwd`; inspect its shell and run `sudo -l -U telemetry-sync` | Password-login account using the range starter password with unrestricted passwordless sudo | Remove `/etc/sudoers.d/telemetry-sync`, lock/remove the account and review authentication logs |
| `plinko-update-check` | `find / -xdev -perm -4000 -type f 2>/dev/null`; inspect it with `file` | Setuid-root Python interpreter that permits effective-UID escalation | Capture hash and remove `/usr/local/libexec/plinko-update-check` |
| `bishop-agent` process | `grep --no-messages bishop /proc/*/exe`; inspect `systemctl status plinko-telemetry-agent` | Running Sliver-like process indicator disconnected from C2 | Stop/disable `plinko-telemetry-agent.service`, remove its unit and executable |
| Netcat listener | `ss -lntp`; inspect `plinko-maintenance-listener` | Root command shell listening on TCP 4444 through `nc.traditional` | Block TCP 4444, stop/disable the service, and remove its unit |
| Persistence jobs | Inspect `atq`, `/usr/local/sbin/plinko-listener-revive`, and `plinko-health-refresh.*` | Recurring `at` job revives the command listener; an active timer refreshes a hidden marker | Remove queued jobs/helper and disable/remove the timer and listener units |
| `libhorsehide` preload | Inspect `/etc/ld.so.preload` from a trusted static environment and hash `/usr/local/lib/libhorsehide.so` | System-wide preload library filters selected names from directory listings | Preserve the library, remove its preload entry from recovery media, then remove the library and verify system binaries |

After cleanup, verify `sshd`, Apache, PlinkCom login, the dashboard API, and MariaDB connectivity.

## Ignition

| Finding | How to find it | Installed behavior | Remediation |
| --- | --- | --- | --- |
| `support.bot@plinko.horse` | Open WebUI admin panel or its Users API | Live unauthorized Open WebUI account | Delete/disable the account and review chats/tokens |
| `flight-cache` account | `getent passwd`; inspect its shell and `/etc/sudoers.d/flight-cache` | Password-login account using the range starter password with unrestricted passwordless sudo | Remove its sudo rule, lock/remove the account and review authentication logs |
| `launch-diagnostics` | `find / -xdev -perm -4000 -type f 2>/dev/null` | Setuid-root executable that starts a privileged Bash shell | Hash and remove `/usr/local/libexec/launch-diagnostics` |
| `telemetry-indexer` process | `systemctl status telemetry-indexer`; inspect `/proc/*/exe` | Running IMIX-like process indicator disconnected from C2 | Disable/remove the service and `/opt/ihpl-training/telemetry-indexer` |
| Root cron entry | Inspect `/etc/cron.d/telemetry-index-refresh` | Active root cron job that revives the disconnected IMIX process indicator every minute | Remove `/etc/cron.d/telemetry-index-refresh` |
| Downloads backdoor | `find /home -path '*/Downloads/*' -ls`; inspect `telemetry-viewer.service` and TCP 4545 | Active TCP command shell running as `jmoney` from `/home/jmoney/Downloads/telemetry_viewer` | Block TCP 4545, stop/disable the service, preserve/hash and remove `telemetry_viewer`, and review shell history |
| Suspicious environment file | `find /etc -type f -mtime -30`; inspect `/etc/profile.d/telemetry-debug.sh` | Active environment persistence applied to new login sessions | Remove the file and start fresh sessions |

Verify SSH, the `open-webui` container, the local `plinkai-stub` service, login as `jmoney@plinko.horse`, and a short PlinkAI chat.

## Assembly

| Finding | How to find it | Installed behavior | Remediation |
| --- | --- | --- | --- |
| `buildsvc` and `former.intern` | Jenkins **Manage Users**; inspect `init.groovy.d` | Live unauthorized Jenkins users with full authenticated control; Jenkins runs as LocalSystem, so job configuration provides command execution | Preserve then remove `10-ihpl-bootstrap.groovy`, delete both users, rotate tokens/passwords, inspect builds |
| Anonymous read | Jenkins security settings or unauthenticated GET | Live excessive authorization setting | Disable anonymous read and adopt role/matrix authorization |
| Writable staging folder | `Get-Acl C:\ProgramData\IHPL\Staging` | Live `Users:Modify` ACL | Remove `Users:Modify`; grant only Jenkins service and administrators |
| Scheduled inventory task | `Get-ScheduledTask -TaskPath '\IHPL\'` | Active task running every minute as SYSTEM | Export for evidence, unregister `IHPL Build Inventory` |
| Writable SYSTEM command path | Inspect `C:\ProgramData\IHPL\Staging\release.cmd`, its ACL, and `IHPL Build Inventory` | Built-in Users can replace a batch file executed every minute as SYSTEM | Unregister the task, remove the command file, and restrict the staging ACL |
| Legacy OS accounts | Enumerate local users and Remote Desktop Users | `flightops-old` and `rocketvendor` are enabled for RDP with the starter password | Disable/remove both users and review RDP authentication logs |

Validate both job results, Jenkins login, RDP, and connectivity from Assembly to Manifest TCP 3306.

## Manifest

| Finding | How to find it | Installed behavior | Remediation |
| --- | --- | --- | --- |
| `telemetry_admin@localhost` | `SELECT User,Host,account_locked FROM mysql.user;` | Live unauthorized MariaDB administrator with global privileges | Revoke, drop the account, rotate affected credentials, review MariaDB logs |
| TCP 4444 bind shell | `Get-NetTCPConnection -LocalPort 4444 -State Listen`; inspect owning process/task | Network-accessible SYSTEM command shell started by `IHPL Local Diagnostics` | Block TCP 4444, stop and unregister the task, and remove the script |
| `manifest-indexer` heartbeat | `Get-ScheduledTask -TaskPath '\IHPL\'`; inspect training logs | Active scheduled heartbeat serving as a disconnected IMIX-like process/persistence indicator | Unregister task and remove its script/logs |
| `win-update-helper.exe.training` | Search `C:\ProgramData\IHPL\Training` and startup paths | Non-executing Sliver-like implant marker disconnected from C2 | Preserve/hash, delete marker and any startup reference |
| `dbmaint` local user | Enumerate local accounts through Computer Management or the WinNT provider; inspect Administrators membership | Enabled administrator/RDP account using the range starter password | Disable/remove the account, rotate credentials, and review RDP logs |
| Broad data ACL | `Get-Acl C:\ProgramData\MariaDB\data` | Live read/execute access for built-in Users across the MariaDB data tree | Remove `Users` access; retain SYSTEM, Administrators, and MariaDB service identity |

Verify RDP, MariaDB service state, firewall scope, application access from Guidance, and both `jmoney` and PlinkCom read paths after cleanup.
