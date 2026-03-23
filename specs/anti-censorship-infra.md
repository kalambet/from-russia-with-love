# Spec: Anti-Censorship Proxy Infrastructure (mtg + Outline VPN)

**Date**: 2026-03-23
**Author**: Peter, with AI assistance
**Status**: Draft

## Motivation

Family members in Russia need reliable access to Telegram and the open internet despite RKN (Roskomnadzor) blocking. The infrastructure must support rapid redeployment when IPs get blocked — destroy the blocked node, spin up a fresh one with a new IP, and share updated credentials within minutes.

## Goal

- Deploy **mtg** (MTProxy for Telegram) on one VPS and **Outline VPN** on another
- Service-to-provider mapping is **configurable** (either service on either provider)
- Providers: **Vultr** and **Linode**
- Single-command destroy-and-recreate workflow for blocked nodes
- Credentials output saved to a local file for manual sharing
- Future: Telegram bot triggers redeployment (out of scope for now)

## Scope

- **Hosts/Groups**: Two dynamically provisioned VPS nodes (Debian 12, 1 CPU/1GB)
- **Services**: mtg (Docker), Outline/Shadowbox (Docker), UFW firewall
- **Providers**: Vultr (`vultr.cloud` collection), Linode (`linode.cloud` collection)
- **Control node**: User's local machine (macOS or Linux), secrets via 1Password CLI

## Proposed Changes

### Repository Structure

```
from-russia-with-love/
├── ansible.cfg
├── requirements.yml              # Galaxy collections
├── inventory/
│   ├── hosts.yml                 # Static fallback / local
│   └── group_vars/
│       ├── all.yml               # Shared defaults
│       ├── mtg.yml               # mtg-specific vars
│       └── outline.yml           # Outline-specific vars
├── roles/
│   ├── common/                   # Base server setup
│   │   ├── tasks/main.yml        # apt update, Docker install, UFW
│   │   └── handlers/main.yml
│   ├── mtg/                      # MTProxy deployment
│   │   ├── tasks/main.yml
│   │   ├── templates/config.toml.j2
│   │   └── handlers/main.yml
│   └── outline/                  # Outline VPN deployment
│       ├── tasks/main.yml
│       └── handlers/main.yml
├── playbooks/
│   ├── provision.yml             # Create VPS on provider
│   ├── deploy.yml                # Configure & deploy services
│   ├── destroy.yml               # Tear down VPS
│   ├── redeploy.yml              # destroy + provision + deploy (single command)
│   └── credentials.yml           # Fetch and save current credentials
├── specs/
│   └── anti-censorship-infra.md  # This spec
└── credentials/                  # .gitignored — local credential output
    └── .gitkeep
```

### Files to Create

#### `ansible.cfg`
Ansible configuration — inventory path, SSH settings, collections path.

#### `requirements.yml`
Galaxy collections: `vultr.cloud`, `linode.cloud`, `community.docker`, `community.general`.

#### `inventory/hosts.yml`
Minimal inventory with `mtg` and `outline` groups. Hosts populated dynamically after provisioning via `add_host`.

#### `inventory/group_vars/all.yml`
Shared variables:
- `vps_os: "Debian 12"`
- `vps_plan_vultr: "vc2-1c-1gb"`
- `vps_plan_linode: "g6-nanode-1"`
- `ssh_public_key_path`
- `credentials_output_dir: "./credentials"`

#### `inventory/group_vars/mtg.yml`
- `mtg_docker_image: "nineseconds/mtg:2"`
- `mtg_port: 443`
- `mtg_fronting_domain: "google.com"`
- `mtg_provider: "vultr"` (or `"linode"` — configurable)
- `mtg_region: "ams"` (configurable)

#### `inventory/group_vars/outline.yml`
- `outline_provider: "linode"` (or `"vultr"` — configurable)
- `outline_region: "eu-west"`
- `outline_api_port: 60000`
- `outline_access_port: 40000`

#### `roles/common/tasks/main.yml`
1. Wait for SSH to become available
2. `apt update && apt upgrade`
3. Install Docker via `get.docker.com` script (or `community.docker`)
4. Configure UFW: deny all incoming, allow SSH (22), allow service-specific port
5. Enable UFW

#### `roles/mtg/tasks/main.yml`
1. Generate mtg secret: `docker run --rm nineseconds/mtg:2 generate-secret {{ mtg_fronting_domain }}`
2. Template `config.toml` from generated secret
3. Run mtg container: port `{{ mtg_port }}:3128`, mount config, restart policy `always`
4. Generate proxy link: `docker run --rm nineseconds/mtg:2 access /config.toml`
5. Save proxy link to credentials file

#### `roles/mtg/templates/config.toml.j2`
```toml
secret = "{{ mtg_secret }}"
bind-to = "0.0.0.0:3128"
```

#### `roles/outline/tasks/main.yml`
1. Download Outline install script
2. Run install script (installs Shadowbox + Watchtower containers)
3. Capture API URL and cert SHA256 from install output
4. Create first access key via Outline Management API
5. Save access key (ss:// URL) to credentials file

#### `playbooks/provision.yml`
- Takes `target_service` variable (`mtg` or `outline`)
- Reads provider API token from 1Password: `op read "op://Vault/ItemName/field"`
- Provisions VPS on the configured provider using `vultr.cloud.instance` or `linode.cloud.instance`
- Registers SSH key on provider if not present
- Adds new host to in-memory inventory via `add_host`

#### `playbooks/deploy.yml`
- Runs `common` role, then service-specific role (`mtg` or `outline`)
- Outputs credentials to `credentials/{{ target_service }}_credentials.txt`

#### `playbooks/destroy.yml`
- Takes `target_service` variable
- Reads provider API token from 1Password
- Destroys VPS instance on the provider
- Cleans up old credentials file

#### `playbooks/redeploy.yml`
- Import `destroy.yml`, then `provision.yml`, then `deploy.yml`
- Single command: `ansible-playbook playbooks/redeploy.yml -e target_service=mtg`

#### `playbooks/credentials.yml`
- Connects to existing nodes, fetches current proxy link / access key
- Saves to `credentials/` directory

### Variables (Secrets via 1Password CLI)

| Variable | Source | Description |
|----------|--------|-------------|
| `vultr_api_token` | `op read "op://Infrastructure/Vultr/api-token"` | Vultr API v2 token |
| `linode_api_token` | `op read "op://Infrastructure/Linode/api-token"` | Linode API v4 token |
| `ssh_public_key` | `~/.ssh/id_ed25519.pub` | SSH key for VPS access |
| `mtg_secret` | Generated at deploy time | MTProxy secret (regenerated each deploy) |

No Ansible Vault needed — all secrets fetched at runtime via `op` CLI.

### Handlers

- `restart mtg` — restart mtg Docker container
- `restart ufw` — reload UFW rules

## Alternatives Considered

| Alternative | Why not |
|-------------|---------|
| Ansible Vault for secrets | 1Password CLI is better — no encrypted files in repo, shared via family plan |
| Single node with both services | Split reduces blast radius — blocking one IP only kills one service |
| Keep blocked nodes running | Unnecessary cost; destroy-and-recreate is cleaner |
| Terraform for provisioning | Overkill for 2 ephemeral VPS; Ansible can handle provision + configure in one tool |
| Provider firewall via API | UFW on host is simpler and provider-agnostic; can add provider firewall later |

## Dependencies

- `op` CLI installed and authenticated on control node
- 1Password items created: `Infrastructure/Vultr` (with `api-token` field), `Infrastructure/Linode` (with `api-token` field)
- SSH key pair at `~/.ssh/id_ed25519{,.pub}`
- Python 3.x + `ansible-core` >= 2.14 installed
- Galaxy collections installed: `ansible-galaxy install -r requirements.yml`

## Security Considerations

- **No secrets in repo**: All API tokens and credentials fetched via `op` CLI at runtime
- **SSH key only auth**: Password auth disabled on VPS nodes
- **UFW firewall**: Default deny, only service port + SSH allowed
- **mtg secret regenerated** on every fresh deploy — old secrets become useless
- **Outline access keys** regenerated on every fresh deploy
- **Credentials directory** is `.gitignored` — never committed
- **Root access**: Ansible connects as root for initial setup (standard for ephemeral VPS); no long-lived user accounts needed since nodes are disposable

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| New IP also blocked quickly | Medium | Medium | Deploy to different region; rotate providers |
| 1Password CLI auth expires mid-run | Low | Low | Re-auth before running; `op` sessions are typically long |
| Outline install script changes upstream | Low | Medium | Pin script version or vendor it locally |
| Provider API rate limiting | Low | Low | Sequential operations; single VPS at a time |
| Docker Hub rate limiting | Low | Low | Pulls are minimal (2-3 images per deploy) |

### Back-out Criteria
- VPS fails to provision after 3 region attempts → investigate provider status
- Services fail to start → check Docker logs, try different OS image
- New IP blocked within minutes → switch to a different provider/region combo

## Testing Plan

1. **Syntax check**: `ansible-playbook --syntax-check playbooks/provision.yml`
2. **Dry run provision**: Verify `op read` calls work, provider API responds
3. **Deploy mtg first**: Single service, verify proxy link works from a non-Russian IP
4. **Deploy Outline second**: Verify access key works with Outline client
5. **Test redeploy flow**: Run `redeploy.yml` for mtg, verify new IP, new credentials, old node gone
6. **Idempotency**: Run `deploy.yml` twice against same node — no unexpected changes
7. **Test from Russia**: Have family member verify connectivity through both services

## Monitoring & Validation

- **Post-deploy**: Playbook outputs credentials file path and tests port connectivity
- **mtg**: `curl -I https://<ip>:443` should return a TLS handshake (mimicking fronting domain)
- **Outline**: `curl -k https://<ip>:60000/<api-path>/server` should return server info
- **Ongoing**: Manual check — ask family if it works. No monitoring infra needed for 2 disposable nodes
- **Success criteria**: Family members can connect to Telegram (via mtg) and browse freely (via Outline) from Russia

## Rollback

Since nodes are ephemeral and disposable:
- **Rollback = destroy**: `ansible-playbook playbooks/destroy.yml -e target_service=mtg`
- No state to preserve — credentials are regenerated on each deploy
- Rollback time: ~30 seconds (API call to delete VPS)
- Any family member can request a redeploy via Telegram message to Peter

## Implementation Order

1. Set up repo structure, `ansible.cfg`, `requirements.yml`
2. Implement `roles/common` (Docker + UFW)
3. Implement `roles/mtg` (container + config + credential output)
4. Implement `roles/outline` (install script + credential output)
5. Implement `playbooks/provision.yml` (Vultr + Linode support, 1Password integration)
6. Implement `playbooks/deploy.yml`
7. Implement `playbooks/destroy.yml`
8. Implement `playbooks/redeploy.yml`
9. Test end-to-end: provision → deploy → verify → destroy
