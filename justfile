# Anti-censorship proxy infrastructure
# Usage: just deploy mtg, just redeploy outline, just destroy mtg

set dotenv-load := false

playbooks := "playbooks"
default_mtg_region_vultr := "ams"
default_mtg_region_linode := "eu-west"
default_outline_region_vultr := "ams"
default_outline_region_linode := "eu-west"

# List available recipes
default:
    @just --list

# Install Ansible Galaxy collections
setup:
    ansible-galaxy collection install -r requirements.yml

# Provision a new VPS (service: mtg or outline)
provision service region="":
    ansible-playbook {{playbooks}}/provision.yml \
        -e target_service={{service}} \
        {{ if region != "" { "-e " + service + "_region_vultr=" + region + " -e " + service + "_region_linode=" + region } else { "" } }}

# Deploy service to a provisioned VPS
deploy service host="":
    ansible-playbook {{playbooks}}/deploy.yml \
        -e target_service={{service}} \
        {{ if host != "" { "-e target_host=" + host } else { "" } }}

# Provision + deploy in one step
up service region="":
    just provision {{service}} {{region}}
    #!/usr/bin/env bash
    set -euo pipefail
    HOST=$(cat credentials/{{service}}_host_ip.txt)
    just deploy {{service}} "$HOST"

# Destroy a VPS
destroy service:
    ansible-playbook {{playbooks}}/destroy.yml \
        -e target_service={{service}}

# Redeploy: destroy + provision + deploy (new IP)
redeploy service region="":
    ansible-playbook {{playbooks}}/redeploy.yml \
        -e target_service={{service}} \
        {{ if region != "" { "-e " + service + "_region_vultr=" + region + " -e " + service + "_region_linode=" + region } else { "" } }}

# Fetch credentials from a running node
creds service host="":
    ansible-playbook {{playbooks}}/credentials.yml \
        -e target_service={{service}} \
        {{ if host != "" { "-e target_host=" + host } else { "" } }}

# Show saved credentials
show service:
    @cat credentials/{{service}}_credentials.txt 2>/dev/null || echo "No credentials found for {{service}}. Run: just up {{service}}"

# Show saved host IP
ip service:
    @cat credentials/{{service}}_host_ip.txt 2>/dev/null || echo "No host IP found for {{service}}"

# Deploy everything (mtg + outline)
up-all:
    just up mtg
    just up outline

# Destroy everything
destroy-all:
    just destroy mtg
    just destroy outline

# Redeploy everything with fresh IPs
redeploy-all:
    just redeploy mtg
    just redeploy outline

# Syntax check all playbooks
check:
    @for pb in provision deploy destroy redeploy credentials; do \
        echo "Checking {{playbooks}}/$pb.yml..."; \
        ansible-playbook --syntax-check {{playbooks}}/$pb.yml; \
    done

# Dry run a deploy (check mode)
dry-run service host:
    ansible-playbook {{playbooks}}/deploy.yml \
        -e target_service={{service}} \
        -e target_host={{host}} \
        --check --diff
