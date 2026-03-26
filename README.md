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

- **Python 3.x** with `venv` support
- **just** — command runner ([https://github.com/casey/just](https://github.com/casey/just))
- **1Password CLI** (`op`) — installed and authenticated
- **1Password items**:
  - `Infrastructure/Vultr` with field `api-token`
  - `Infrastructure/Linode` with field `api-token`
  - SSH public key stored at `op://Infrastructure/ssh-key/public key`
- **For Outline users**: Outline client app (iOS, Android, macOS, Windows, Linux) and Outline Manager for server management
- **For Telegram users**: no special client needed — proxy link works in the standard Telegram app

## Quick Start

```bash
just setup                # Create venv, install Python deps + Galaxy collections
just up mtg vultr         # Provision + deploy MTProxy on Vultr
just up outline linode    # Provision + deploy Outline VPN on Linode
just show mtg             # Display proxy link to share
just show outline         # Display access keys + management JSON
```

## Commands Reference

| Command | Description | Example |
|---------|-------------|---------|
| `just` | List all available recipes | `just` |
| `just setup` | Create venv, install Python deps and Galaxy collections | `just setup` |
| `just provision <service> <provider> [region]` | Provision a new VPS | `just provision mtg vultr fra` |
| `just deploy <service>` | Deploy service (hosts auto-discovered from inventory) | `just deploy mtg` |
| `just up <service> <provider> [region]` | Provision + deploy in one step | `just up outline linode` |
| `just destroy <service> [provider]` | Destroy a VPS (provider auto-detected if omitted) | `just destroy mtg` |
| `just redeploy <service> <provider> [region]` | Destroy + provision + deploy (new IP) | `just redeploy mtg vultr fra` |
| `just creds <service>` | Fetch credentials from running nodes | `just creds outline` |
| `just show <service> [provider]` | Show saved credentials | `just show mtg linode` |
| `just hosts` | List all hosts from dynamic inventory | `just hosts` |
| `just hosts-for <service>` | List hosts for a specific service | `just hosts-for mtg` |
| `just up-all [mtg_provider] [outline_provider]` | Deploy everything | `just up-all vultr linode` |
| `just destroy-all` | Destroy everything | `just destroy-all` |
| `just redeploy-all [mtg_provider] [outline_provider]` | Redeploy everything with fresh IPs | `just redeploy-all` |
| `just check` | Syntax check all playbooks | `just check` |
| `just dry-run <service>` | Dry run a deploy (check mode) | `just dry-run mtg` |

Service values: `mtg` or `outline`. Provider values: `vultr` or `linode`.

## Redeployment (When Blocked)

When a node gets blocked by RKN, redeploy to get a new IP:

```bash
just redeploy mtg vultr              # Same provider + region, new IP
just redeploy mtg vultr fra          # Switch to Frankfurt
just redeploy mtg linode             # Switch provider entirely
just redeploy outline linode fr-par-2 # Switch Outline region
```

The redeploy workflow: destroy existing node → provision a new one → deploy the service → save fresh credentials. Credentials are regenerated automatically (new mtg secret, new Outline access keys) and saved to the `credentials/` directory. Share the new link/key with family.

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
| `outline_key_names` | `["mom", "dad", "sister"]` | Access key recipients — one named key per person, shown in Outline Manager |

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
| `provider_region` | `eu-central` | Default region (Frankfurt) |
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

## Credentials

Credentials are saved locally in the `credentials/` directory (gitignored) using the naming convention `<service>-<provider>_credentials.txt`.

**MTProxy credentials** include the Telegram proxy link (share directly with users).

**Outline credentials** include:
- Named access keys for each recipient in `outline_key_names` (share the `ss://` URL with each person)
- Management JSON with `apiUrl` and `certSha256` (paste into Outline Manager to manage the server)

To update the recipient list, edit `outline_key_names` in `inventory/group_vars/outline.yml` and run `just deploy outline`. Keys not in the list are removed, missing ones are created.

## Project Structure

```
from-russia-with-love/
├── ansible.cfg                           # Ansible config (inventory, SSH, pipelining)
├── justfile                              # Command runner recipes
├── requirements.yml                      # Galaxy collections (vultr, linode, docker, general)
├── requirements.txt                      # Python dependencies (ansible-core, linode_api4, etc.)
├── providers/
│   ├── vultr.yml                         # Vultr infra: plan, image, region, 1Password path
│   └── linode.yml                        # Linode infra: plan, image, region, 1Password path
├── inventory/
│   ├── vultr.yml                         # Vultr dynamic inventory plugin
│   ├── linode.yml                        # Linode dynamic inventory plugin
│   ├── .disabled/                        # Inventory plugins moved here when token unavailable
│   └── group_vars/
│       ├── all.yml                       # Shared: credentials dir, 1Password vault, SSH key
│       ├── mtg.yml                       # mtg service config (port, fronting, image, label)
│       └── outline.yml                   # Outline service config (ports, label, key recipients)
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
│       └── tasks/main.yml               # Install Outline, manage access keys, save credentials
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
- **SSH key from 1Password** — public key read from `op://Infrastructure/ssh-key/public key`, Ansible authenticates via SSH agent
- **SSH key-only auth** — password authentication disabled on all nodes
- **UFW firewall** — default deny incoming, only service ports + SSH (rate-limited) allowed
- **Credentials files** are `0600`, directories `0700`
- **Host key verification enabled** — `StrictHostKeyChecking=accept-new` for new hosts; stale keys auto-removed on reprovision
- **`.gitignore`** excludes `credentials/` directory
- **Dynamic inventory auto-disable** — inventory plugins are moved to `.disabled/` when their API token is unavailable, preventing auth errors

## Known Limitations

- **Outline install script** is fetched from upstream without checksum pinning — a compromised upstream could affect new deploys.
- **No automated monitoring** — verification is manual, via family feedback ("does it work?").

## Adding a New Provider

1. Create `providers/<name>.yml` with `provider_name`, `provider_plan`, `provider_image`, `provider_op_item`, `provider_region`
2. Create `roles/provider_<name>/tasks/main.yml` — provision logic, must set `new_host_ip` fact
3. Create `roles/provider_<name>/tasks/destroy.yml` — teardown logic
4. Add the Galaxy collection to `requirements.yml`
5. Create the 1Password item with an `api-token` field
6. Add dynamic inventory plugin config to `inventory/<name>.yml`
7. Add the sync-inventory logic for the new provider in the `justfile`

Then use it: `just up mtg <name>`

## Future Plans

- Telegram bot for triggering redeployment (family members request new IP via bot)
- Automated region rotation on block detection
- Additional providers (Hetzner, DigitalOcean)

## License

MIT
