# from-russia-with-love

Ansible infrastructure for deploying anti-censorship proxy nodes — **mtg** (MTProxy for Telegram) and **Outline VPN** (Shadowsocks) — across Vultr and Linode. Designed for rapid redeployment when IPs get blocked by RKN (Roskomnadzor). Destroy the blocked node, spin up a fresh one with a new IP, share updated credentials — all in one command.

## Architecture

Two separate VPS nodes, each running a single service in Docker:

- **mtg** — MTProxy for Telegram (default: Vultr, Amsterdam)
- **Outline VPN** — Shadowsocks-based VPN via Jigsaw's Outline (default: Linode, EU West)

Services are split across providers to reduce blast radius — blocking one IP only kills one service. Service-to-provider mapping is configurable; either service can run on either provider. Nodes are ephemeral: destroy and recreate for a new IP. Credentials are regenerated on every deploy.

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
just setup          # Install Galaxy collections
just up mtg         # Provision + deploy MTProxy
just up outline     # Provision + deploy Outline VPN
just show mtg       # Display proxy link to share
just show outline   # Display access key to share
```

## Commands Reference

| Command | Description | Example |
|---------|-------------|---------|
| `just` | List all available recipes | `just` |
| `just setup` | Install Ansible Galaxy collections | `just setup` |
| `just provision <service> [region]` | Provision a new VPS | `just provision mtg fra` |
| `just deploy <service> [host]` | Deploy service to a provisioned VPS | `just deploy mtg 1.2.3.4` |
| `just up <service> [region]` | Provision + deploy in one step | `just up outline eu-west` |
| `just destroy <service>` | Destroy a VPS | `just destroy mtg` |
| `just redeploy <service> [region]` | Destroy + provision + deploy (new IP) | `just redeploy mtg fra` |
| `just creds <service> [host]` | Fetch credentials from a running node | `just creds outline 1.2.3.4` |
| `just show <service>` | Show saved credentials | `just show mtg` |
| `just ip <service>` | Show saved host IP | `just ip outline` |
| `just up-all` | Deploy everything (mtg + outline) | `just up-all` |
| `just destroy-all` | Destroy everything | `just destroy-all` |
| `just redeploy-all` | Redeploy everything with fresh IPs | `just redeploy-all` |
| `just check` | Syntax check all playbooks | `just check` |
| `just dry-run <service> <host>` | Dry run a deploy (check mode) | `just dry-run mtg 1.2.3.4` |

Service values: `mtg` or `outline`.

## Redeployment (When Blocked)

When a node gets blocked by RKN, redeploy to get a new IP:

```bash
just redeploy mtg              # Same region, new IP
just redeploy mtg fra          # Switch to Frankfurt
just redeploy outline eu-west  # Switch Outline region
```

The redeploy workflow: destroy existing node, provision a new one, deploy the service, save fresh credentials. Credentials are regenerated automatically (new mtg secret, new Outline access key) and saved to the `credentials/` directory. Share the new link/key with family.

## Configuration

### Key Variables

**`inventory/group_vars/mtg.yml`**:

| Variable | Default | Description |
|----------|---------|-------------|
| `mtg_provider` | `vultr` | Cloud provider (`vultr` or `linode`) |
| `mtg_region_vultr` | `ams` | Vultr region code |
| `mtg_region_linode` | `eu-west` | Linode region code |
| `mtg_port` | `443` | External port (443 mimics HTTPS) |
| `mtg_fronting_domain` | `google.com` | Domain fronting target for obfuscation |

**`inventory/group_vars/outline.yml`**:

| Variable | Default | Description |
|----------|---------|-------------|
| `outline_provider` | `linode` | Cloud provider (`vultr` or `linode`) |
| `outline_region_vultr` | `ams` | Vultr region code |
| `outline_region_linode` | `eu-west` | Linode region code |
| `outline_api_port` | `60000` | Outline management API port |
| `outline_access_port` | `40000` | Outline client access port |

**`inventory/group_vars/all.yml`**:

| Variable | Default | Description |
|----------|---------|-------------|
| `vps_plan_vultr` | `vc2-1c-1gb` | Vultr instance plan |
| `vps_plan_linode` | `g6-nanode-1` | Linode instance plan |
| _(SSH keys)_ | _(from agent)_ | Public key read from SSH agent via `ssh-add -L` |
| `op_vault` | `Infrastructure` | 1Password vault name |
| `op_vultr_item` | `Vultr` | 1Password item for Vultr API token |
| `op_linode_item` | `Linode` | 1Password item for Linode API token |

### Switching Providers

To move mtg from Vultr to Linode, edit `inventory/group_vars/mtg.yml`:

```yaml
mtg_provider: "linode"
mtg_region_linode: "eu-west"
```

Then redeploy: `just redeploy mtg`

## Project Structure

```
from-russia-with-love/
├── ansible.cfg                        # Ansible config (inventory, SSH, pipelining)
├── justfile                           # Command runner recipes
├── requirements.yml                   # Galaxy collections (vultr, linode, docker, general)
├── inventory/
│   ├── hosts.yml                      # Static inventory (groups only, hosts added dynamically)
│   └── group_vars/
│       ├── all.yml                    # Shared variables (VPS plans, SSH, 1Password paths)
│       ├── mtg.yml                    # mtg service config (provider, region, port, fronting)
│       └── outline.yml                # Outline service config (provider, region, ports)
├── roles/
│   ├── common/
│   │   ├── tasks/main.yml             # Base setup: apt, Docker, UFW, SSH hardening
│   │   └── handlers/main.yml          # Handler: restart sshd
│   ├── mtg/
│   │   ├── tasks/main.yml             # Generate secret, run container, save proxy link
│   │   ├── templates/config.toml.j2   # mtg config template
│   │   └── handlers/main.yml          # Handler: restart mtg container
│   └── outline/
│       └── tasks/main.yml             # Install Outline, create access key, save credentials
├── playbooks/
│   ├── provision.yml                  # Create VPS on Vultr or Linode
│   ├── deploy.yml                     # Run common + service role on provisioned node
│   ├── destroy.yml                    # Tear down VPS and clean up credentials
│   ├── redeploy.yml                   # Destroy + provision + deploy (single command)
│   └── credentials.yml                # Fetch credentials from running nodes
├── specs/
│   └── anti-censorship-infra.md       # Design spec
├── credentials/                       # .gitignored — local credential output
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

## Future Plans

- Telegram bot for triggering redeployment (family members request new IP via bot)
- Automated region rotation on block detection
- Provider firewall rules via API (defense in depth beyond UFW)

## License

MIT
