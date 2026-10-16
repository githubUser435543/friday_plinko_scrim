# Ignition — Open WebUI and PlinkAI

Ignition is a Fedora Server 39 host running OpenSSH and Open WebUI v0.11.3 in Podman. A tiny local OpenAI-compatible service exposes the `PlinkAI` model so the exercise does not need an external API key or Ollama host.

Fedora 39 is end-of-life. The installer first uses configured repositories and, if their metadata is unavailable, switches package installation to Fedora's signed archive repositories. It leaves GPG verification enabled.

## Install

```bash
sudo ./setup.sh \
  --ignition-ip 198.18.6.107 \
  --password 'H00ves0nTheM00n'
```

Use `--skip-training-artifacts` for a clean service-only build. Re-running the command refreshes the container and configuration without deleting `/var/lib/open-webui`.

Public signup stays disabled while Open WebUI permits the installer to bootstrap the first administrator. The installer then authenticates as that administrator and creates or synchronizes the `jmoney` and unauthorized `support.bot` accounts through Open WebUI's authenticated user-management API. It verifies that both accounts appear in the administrator's user list and can sign in before setup continues. This also lets a rerun repair a previous run that stopped immediately after creating `plinktern@plinko.horse`.

The installer also overwrites Open WebUI's persistent OpenAI-compatible connection with `http://host.containers.internal:11435/v1`. Open WebUI v0.11.3 hides unregistered provider models from ordinary users by default, so this single-model training host enables `BYPASS_MODEL_ACCESS_CONTROL` to expose PlinkAI to the scoring account. It sets PlinkAI as the global default, pinned model, background task model, and `jmoney`'s saved selection. Setup signs in as `jmoney`, confirms the browser receives that default, and tests both ordinary and streaming chat completions after Open WebUI starts in its final configuration.

## Verification

```bash
systemctl --no-pager status sshd plinkai-stub open-webui
curl -fsS http://127.0.0.1:11435/v1/models
curl -fsS http://127.0.0.1/health
podman exec open-webui python3 -c "import urllib.request; print(urllib.request.urlopen('http://host.containers.internal:11435/v1/models').read().decode())"
podman logs --tail 50 open-webui
id jmoney
id plinktern
```

Browse to Ignition and sign in as `plinktern@plinko.horse` for administration or `jmoney@plinko.horse` for scoring. The matching OS accounts also exist with the same starter password; `plinktern` belongs to `wheel` and `jmoney` does not.

Open WebUI data persists at `/var/lib/open-webui`. Back up that directory before upgrades. The image tag defaults to exactly `v0.11.3`; override `--open-webui-version` only for a deliberate upgrade exercise.
