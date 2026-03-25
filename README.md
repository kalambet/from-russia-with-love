# from-russia-with-love

Ansible infrastructure for deploying anti-censorship proxy nodes — **mtg** (MTProxy for Telegram) and **Outline VPN** (Shadowsocks) — across Vultr and Linode. Designed for rapid redeployment when IPs get blocked by RKN (Roskomnadzor). Destroy the blocked node, spin up a fresh one with a new IP, share updated credentials — all in one command.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐
│   Services      │     │   Providers     │
│  (what to run)  │     │  (where to run) │
├─────────────────┤     ├─────────────────┤
│  mtg            │ ──▶ │  vultr          │
│  outline        │ ──▶ │  linode         │
└─────────────────┘     └─────────────────┘
```

**Services** define *what* to run — Docker image, ports, application config. They know nothing about infrastructure.

**Providers** define *where* and *how* — API credentials, region, instance plan, OS image. They are the single source of truth for all infra details.

Any service can deploy on any provider. Nodes are ephemeral: destroy and recreate for a new IP. Credentials are regenerated on every deploy.

## Prerequisites

- **Ansible core** >= 2.14 (with Python 3.x)
- **just** — command runner ([https://github.com/casey/just](https://github.com/casey/just))
- **1Password CLI** (`op`) — installed and authenticated
- **1Password items**:
  - `Infrastructure/Vultr` with field `api-token`
  - `Infrastructure/Linode` with field `api-token`
- **SSH agent** with a key loaded (`ssh-add` — the playbook reads the public key from the agent via `ssh-add -L`)
- **For Outline users**: Outline client app (iOS, Android, macOS, Windows, Linux)
- **For Telegram users**: no special client needed — proxy link works in the standard Telegram app

## Quick Start

```bash
just setup                # Install Galaxy collections
just up mtg vultr         # Provision + deploy MTProxy on Vultr
just up outline linode    # Provision + deploy Outline VPN on Linode
just show mtg             # Display proxy link to share
just show outline         # Display access key to share
```

## Commands Reference

| Command | Description | Example |
|---------|-------------|---------|
| `just` | List all available recipes | `just` |
| `just setup` | Install Ansible Galaxy collections | `just setup` |
| `just provision <service> <provider> [region]` | Provision a new VPS | `just provision mtg vultr fra` |
| `just deploy <service> [host]` | Deploy service to a provisioned VPS | `just deploy mtg 1.2.3.4` |
| `just up <service> <provider> [region]` | Provision + deploy in one step | `just up outline linode` |
| `just destroy <service> [provider]` | Destroy a VPS (provider auto-detected if omitted) | `just destroy mtg` |
| `just redeploy <service> <provider> [region]` | Destroy + provision + deploy (new IP) | `just redeploy mtg vultr fra` |
| `just creds <service> [host]` | Fetch credentials from a running node | `just creds outline 1.2.3.4` |
| `just show <service>` | Show saved credentials | `just show mtg` |
| `just ip <service>` | Show saved host IP | `just ip outline` |
| `just up-all [mtg_provider] [outline_provider]` | Deploy everything | `just up-all vultr linode` |
| `just destroy-all` | Destroy everything | `just destroy-all` |
| `just redeploy-all [mtg_provider] [outline_provider]` | Redeploy everything with fresh IPs | `just redeploy-all` |
| `just check` | Syntax check all playbooks | `just check` |
| `just dry-run <service> <host>` | Dry run a deploy (check mode) | `just dry-run mtg 1.2.3.4` |

Service values: `mtg` or `outline`. Provider values: `vultr` or `linode`.

## Redeployment (When Blocked)

When a node gets blocked by RKN, redeploy to get a new IP:

```bash
just redeploy mtg vultr              # Same provider + region, new IP
just redeploy mtg vultr fra          # Switch to Frankfurt
just redeploy mtg linode             # Switch provider entirely
just redeploy outline linode eu-west # Switch Outline region
```

The redeploy workflow: destroy existing node → provision a new one → deploy the service → save fresh credentials. Credentials are regenerated automatically (new mtg secret, new Outline access key) and saved to the `credentials/` directory. Share the new link/key with family.

## Configuration

### Services (`inventory/group_vars/`)

Service configs are provider-agnostic — they define *what* to run, not *where*.

**`mtg.yml`**:

| Variable | Default | Description |
|----------|---------|-------------|
| `mtg_port` | `443` | External port (443 mimics HTTPS) |
| `mtg_fronting_domain` | `google.com` | Domain fronting target for obfuscation |
| `mtg_docker_image` | `nineseconds/mtg:2` | Docker image |
| `mtg_label` | `mtg-proxy` | VPS instance label |

**`outline.yml`**:

| Variable | Default | Description |
|----------|---------|-------------|
| `outline_api_port` | `60000` | Outline management API port |
| `outline_access_port` | `40000` | Outline client access port |
| `outline_label` | `outline-vpn` | VPS instance label |

### Providers (`providers/`)

Provider configs are the single source of truth for all infrastructure details.

**`vultr.yml`**:

| Variable | Default | Description |
|----------|---------|-------------|
| `provider_plan` | `vc2-1c-1gb` | Instance plan (1 CPU, 1GB RAM) |
| `provider_image` | `Debian 12 x64 (bookworm)` | OS image |
| `provider_region` | `ams` | Default region (Amsterdam) |
| `provider_op_item` | `Vultr` | 1Password item name for API token |

**`linode.yml`**:

| Variable | Default | Description |
|----------|---------|-------------|
| `provider_plan` | `g6-nanode-1` | Instance plan (1 CPU, 1GB RAM) |
| `provider_image` | `linode/debian12` | OS image |
| `provider_region` | `eu-west` | Default region (EU West) |
| `provider_op_item` | `Linode` | 1Password item name for API token |

### Switching Providers

Provider is chosen at deploy time — just pass a different provider:

```bash
# Move mtg from Vultr to Linode
just redeploy mtg linode

# Move Outline from Linode to Vultr
just redeploy outline vultr fra
```

No config files need editing to switch providers.

## Project Structure

```
from-russia-with-love/
├── ansible.cfg                           # Ansible config (inventory, SSH, pipelining)
├── justfile                              # Command runner recipes
├── requirements.yml                      # Galaxy collections (vultr, linode, docker, general)
├── providers/
│   ├── vultr.yml                         # Vultr infra: plan, image, region, 1Password path
│   └── linode.yml                        # Linode infra: plan, image, region, 1Password path
├── inventory/
│   ├── hosts.yml                         # Static inventory (groups only, hosts added dynamically)
│   └── group_vars/
│       ├── all.yml                       # Shared: credentials dir, 1Password vault
│       ├── mtg.yml                       # mtg service config (port, fronting, image, label)
│       └── outline.yml                   # Outline service config (ports, label)
├── roles/
│   ├── provider_vultr/
│   │   └── tasks/
│   │       ├── main.yml                  # Provision: API token → SSH key → create instance
│   │       └── destroy.yml               # Destroy: API token → delete instance
│   ├── provider_linode/
│   │   └── tasks/
│   │       ├── main.yml                  # Provision: API token → create instance
│   │       └── destroy.yml               # Destroy: API token → delete instance
│   ├── common/
│   │   ├── tasks/main.yml               # Base setup: apt, Docker, UFW, SSH hardening
│   │   └── handlers/main.yml            # Handler: restart sshd
│   ├── mtg/
│   │   ├── tasks/main.yml               # Generate secret, run container, save proxy link
│   │   ├── templates/config.toml.j2     # mtg config template
│   │   └── handlers/main.yml            # Handler: restart mtg container
│   └── outline/
│       └── tasks/main.yml               # Install Outline, create access key, save credentials
├── playbooks/
│   ├── provision.yml                     # Create VPS via provider role
│   ├── deploy.yml                        # Run common + service role on provisioned node
│   ├── destroy.yml                       # Tear down VPS via provider role
│   ├── redeploy.yml                      # Destroy + provision + deploy (single command)
│   └── credentials.yml                   # Fetch credentials from running nodes
├── specs/
│   └── anti-censorship-infra.md          # Design spec
├── credentials/                          # .gitignored — local credential output
└── .gitignore
```

## Security

- **No secrets in repo** — all API tokens fetched via 1Password CLI (`op`) at runtime
- **SSH agent** — no private key paths in config; public key read from agent at runtime, Ansible authenticates via agent
- **SSH key-only auth** — password authentication disabled on all nodes
- **UFW firewall** — default deny incoming, only service port + SSH (rate-limited) allowed
- **Credentials files** are `0600`, directories `0700`
- **`no_log: true`** on all tasks handling secrets (API tokens, mtg secrets, Outline keys)
- **Host key verification enabled** — `StrictHostKeyChecking=accept-new` for ephemeral nodes
- **`.gitignore`** excludes `credentials/` directory

## Known Limitations

- **Docker bypasses UFW** for port mapping — the Outline management API port (`60000`) may be externally reachable despite UFW rules. The API requires the cert SHA256 for authentication, which provides some protection. Consider adding `iptables` DOCKER-USER chain rules for defense in depth.
- **Outline install script** is fetched from upstream without checksum pinning — a compromised upstream could affect new deploys.
- **No automated monitoring** — verification is manual, via family feedback ("does it work?").

## Adding a New Provider

1. Create `providers/<name>.yml` with `provider_name`, `provider_plan`, `provider_image`, `provider_op_item`, `provider_region`
2. Create `roles/provider_<name>/tasks/main.yml` — provision logic, must set `new_host_ip` fact
3. Create `roles/provider_<name>/tasks/destroy.yml` — teardown logic
4. Add the Galaxy collection to `requirements.yml`
5. Create the 1Password item with an `api-token` field

Then use it: `just up mtg <name>`

## Future Plans

- Telegram bot for triggering redeployment (family members request new IP via bot)
- Automated region rotation on block detection
- Provider firewall rules via API (defense in depth beyond UFW)
- Additional providers (Hetzner, DigitalOcean)

## License

MIT
