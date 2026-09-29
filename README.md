# Self-Host Hermes Agent with 9Router on Ubuntu

**English** | [فارسی](README.fa.md)

A step-by-step guide to running your own always-on AI agent on a Linux server, reachable from Telegram, with a web dashboard on your own domain.

- **[Hermes Agent](https://github.com/NousResearch/hermes-agent)** — open-source AI agent (Nous Research, MIT license)
- **[9Router](https://github.com/decolua/9router)** — open-source, OpenAI-compatible router/proxy with a web dashboard
- **[Caddy](https://caddyserver.com/)** — reverse proxy with automatic HTTPS

> **Disclaimer:** This is an unofficial community guide. It is not affiliated with Nous Research, 9Router, or Caddy. Free model tiers offered through third-party providers can change or disappear at any time, and you are responsible for following each provider's terms of service.

---

## Table of contents

1. [How it works](#1-how-it-works)
2. [Requirements](#2-requirements)
3. [Prepare the server](#3-prepare-the-server)
4. [Install 9Router](#4-install-9router)
5. [Publish the dashboard with HTTPS](#5-publish-the-dashboard-with-https)
6. [Configure 9Router](#6-configure-9router)
7. [Install Hermes Agent](#7-install-hermes-agent)
8. [Connect Telegram](#8-connect-telegram)
9. [Security checklist](#9-security-checklist)
10. [Troubleshooting](#10-troubleshooting)
11. [Maintenance](#11-maintenance)

---

## 1. How it works

```
Telegram  <-->  Hermes Agent  -->  9Router (127.0.0.1:20128)  -->  AI providers
                                        ^
                       Caddy (HTTPS) ---+   https://ai.example.com/dashboard
```

- Hermes talks to 9Router over `localhost` using the OpenAI-compatible API.
- 9Router holds your provider accounts and API keys and can fall back between models.
- Caddy exposes **only the dashboard** over HTTPS. The 9Router port itself is never opened to the internet.

## 2. Requirements

| Item | Details |
| --- | --- |
| Server | Ubuntu (tested on 26.04 LTS), root or sudo access, 2 GB RAM or more recommended |
| Domain | A domain or subdomain you control (example: `ai.example.com`) |
| Telegram account | To create a bot with `@BotFather` |
| Network | Server can reach `github.com` and your chosen AI providers |

## 3. Prepare the server

```bash
apt update && apt upgrade -y
apt install -y curl git ufw openssl
```

Configure the firewall. **Allow SSH first**, or you will lock yourself out:

```bash
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw status
```

## 4. Install 9Router

**4.1 Install Node.js (version 20 or newer)**

```bash
apt install -y nodejs npm
node -v
```

**4.2 Install 9Router**

```bash
npm install -g 9router
which 9router
```

**4.3 Create the configuration file** (passwords and secrets are generated randomly):

```bash
mkdir -p /etc/9router /var/lib/9router
cat > /etc/9router/env <<EOF
PORT=20128
NODE_ENV=production
DATA_DIR=/var/lib/9router
INITIAL_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=')
JWT_SECRET=$(openssl rand -hex 32)
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 16)
REQUIRE_API_KEY=true
AUTH_COOKIE_SECURE=true
EOF
chmod 600 /etc/9router/env
```

**4.4 Create a systemd service**

> The `HOSTNAME` environment variable is ignored by the 9Router CLI, and without `--host` it binds to `0.0.0.0` (public). Always pass the flags below.

```bash
cat > /etc/systemd/system/9router.service <<'EOF'
[Unit]
Description=9Router
After=network.target

[Service]
EnvironmentFile=/etc/9router/env
ExecStart=/usr/local/bin/9router --host 127.0.0.1 --port 20128 --no-browser --skip-update --log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now 9router
```

**4.5 Verify**

```bash
systemctl status 9router --no-pager | head -n 8
ss -tlnp | grep 20128
```

The `ss` output must show `127.0.0.1:20128`, **not** `0.0.0.0:20128`.

## 5. Publish the dashboard with HTTPS

**5.1 DNS.** Create an `A` record for your subdomain pointing to the server's public IP. If you use Cloudflare, set the record to **DNS only** (grey cloud) for now. Check that it resolves:

```bash
getent hosts ai.example.com
```

**5.2 Install Caddy and configure the reverse proxy** (replace the domain):

```bash
apt install -y caddy
cat > /etc/caddy/Caddyfile <<'EOF'
ai.example.com {
    reverse_proxy 127.0.0.1:20128
}
EOF
systemctl reload caddy || systemctl restart caddy
```

**5.3 Verify.** Caddy obtains a TLS certificate automatically (this can take up to a minute):

```bash
curl -sI https://ai.example.com | head -n 5
```

You should see `HTTP/2 307` with `location: /dashboard`.

## 6. Configure 9Router

1. Read the initial dashboard password (**never share it**):
   ```bash
   grep INITIAL_PASSWORD /etc/9router/env
   ```
2. Open `https://ai.example.com/dashboard` and log in.
3. **Change the password** in the dashboard settings.
4. Open **Providers** and connect at least one provider. Some providers need no sign-up; others need your own API key or OAuth login.
5. Optional: create a **Combo** (a named list of models with automatic fallback). You can use the combo name as the model name in Hermes.
6. Create an **API key** in the endpoint/API keys section.
7. Test the key from the server. Type `read -rs KEY`, press Enter, paste the key, press Enter, then:
   ```bash
   curl -s http://127.0.0.1:20128/v1/models -H "Authorization: Bearer $KEY"
   ```
8. Confirm authentication is actually enforced. This request **without** a key should be rejected:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:20128/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"YOUR_MODEL","messages":[{"role":"user","content":"hi"}]}'
   ```
   Expect `401` or `403`. If you get `200`, treat your endpoint as unauthenticated and keep it on `127.0.0.1` only.

## 7. Install Hermes Agent

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc
hermes --version
```

The first setup wizard asks how to configure Hermes. Choose **Full setup** (not the Nous Portal quick setup), then:

| Wizard question | Answer |
| --- | --- |
| Provider | **Custom endpoint** (near the end of the list) |
| Base URL | `http://127.0.0.1:20128/v1` |
| API key | The 9Router key from step 6 |
| API compatibility mode | `2` — Chat Completions |
| Model | Your combo or model name from 9Router |
| Context length | Leave blank (auto-detect) |
| Display name | Anything, for example `9Router` |
| Terminal backend | `Local` (see the [security checklist](#9-security-checklist)) |
| Messaging platforms | Skip for now |

You can rerun the model selection any time with `hermes model`. Test it:

```bash
hermes
```

Send a short message. If you get a reply, Hermes and 9Router are connected. Exit with `/exit`.

## 8. Connect Telegram

1. In Telegram, talk to `@BotFather`, send `/newbot`, and follow the prompts. Save the **bot token**.
2. Talk to `@userinfobot` to get your numeric **user ID**.
3. On the server:
   ```bash
   hermes gateway setup
   ```
   Select **Telegram** (with `Space`), paste the token, and enter your user ID when asked which users are allowed.
4. Check the background service:
   ```bash
   hermes gateway status
   ```
   The setup installs a `systemd` user service with lingering enabled, so it survives logout and reboots.
5. Send a message to your bot in Telegram.

## 9. Security checklist

- [ ] 9Router listens on `127.0.0.1` only (`ss -tlnp | grep 20128`).
- [ ] Firewall allows only ports 22, 80 and 443.
- [ ] Dashboard password was changed from the initial one.
- [ ] Requests without an API key are rejected (step 6.8).
- [ ] The Telegram bot is restricted to your user ID.
- [ ] Secrets never appear in chats, screenshots, issues or commits. **If a key or password was exposed, delete it and create a new one.** After rotating the Hermes key:
  ```bash
  read -rs NEWKEY
  hermes config set HERMES_CUSTOM_127_0_0_1_20128_API_KEY "$NEWKEY"
  hermes gateway restart
  unset NEWKEY
  ```
  (The variable name is printed by the wizard when it saves the key.)
- [ ] With the `Local` terminal backend the agent runs commands directly on the server, as the user running Hermes. Prefer a dedicated non-root user, and consider isolation:
  ```bash
  hermes config set terminal.backend docker
  ```
  Read every command approval prompt before accepting it.

## 10. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| 9Router restarts in a loop and logs `Exiting...` | Start it with `--host 127.0.0.1 --port 20128 --no-browser --skip-update` as in step 4.4. |
| 9Router is reachable on a public IP | The `--host` flag is missing. Fix the service file, then `systemctl daemon-reload && systemctl restart 9router`. |
| Hermes installer seems stuck after `Cloning` | It is often just quiet. Wait a few minutes. Test with `git clone --progress --depth 1 https://github.com/NousResearch/hermes-agent.git /tmp/t` and delete `/tmp/t` afterwards. |
| `hermes: command not found` | Run `source ~/.bashrc` or open a new shell. |
| Caddy cannot get a certificate | Check the DNS record, that ports 80 and 443 are open, and that no CDN proxy is in front. Read `journalctl -u caddy -n 50`. |
| Wizard demands an API key before 9Router exists | Enter a placeholder, then run `hermes model` after creating the real key. |
| Long chats fail with context errors | Set a smaller window: `hermes config set model.context_length 65536` (Hermes needs at least 64K tokens). |
| Telegram bot is silent | Run `hermes gateway status` and `journalctl --user -u hermes-gateway -n 30 --no-pager`. Check the token and allowed user ID. |
| Anything else in Hermes | `hermes doctor` |

## 11. Maintenance

```bash
hermes update                      # update Hermes
npm update -g 9router              # update 9Router, then: systemctl restart 9router
systemctl status 9router           # service health
journalctl -u 9router -n 50        # 9Router logs
hermes gateway restart             # restart the Telegram gateway
apt update && apt upgrade -y       # system updates
```

---

## Contributing

Issues and pull requests are welcome. Please never include real IP addresses, domains, tokens or passwords in reports.

## License

Documentation released under the MIT License (add a `LICENSE` file to your repository). The tools referenced here are distributed under their own licenses.