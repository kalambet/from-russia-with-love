# Anti-censorship proxy infrastructure
# Usage: just up mtg vultr, just redeploy outline linode fra

set dotenv-load := false

playbooks := "playbooks"
venv := ".venv/bin/"
op_vault := "Infrastructure"

# Export provider API tokens from 1Password for dynamic inventory
# Inventory plugins are auto-enabled/disabled based on token availability
export VULTR_API_KEY := `op read "op://Infrastructure/Vultr/api-token" 2>/dev/null || echo ""`
export LINODE_API_TOKEN := `op read "op://Infrastructure/Linode/api-token" 2>/dev/null || echo ""`
export UPCLOUD_TOKEN := `op read "op://Infrastructure/UpCloud/api-token" 2>/dev/null || echo ""`

# Auto-enable/disable inventory plugins based on available tokens
[private]
sync-inventory:
    #!/usr/bin/env bash
    inv="inventory"
    dis="$inv/.disabled"
    mkdir -p "$dis"
    # Vultr
    if [ -n "$VULTR_API_KEY" ]; then
        [ -f "$dis/vultr.yml" ] && mv "$dis/vultr.yml" "$inv/vultr.yml" || true
    else
        [ -f "$inv/vultr.yml" ] && mv "$inv/vultr.yml" "$dis/vultr.yml" || true
    fi
    # Linode
    if [ -n "$LINODE_API_TOKEN" ]; then
        [ -f "$dis/linode.yml" ] && mv "$dis/linode.yml" "$inv/linode.yml" || true
    else
        [ -f "$inv/linode.yml" ] && mv "$inv/linode.yml" "$dis/linode.yml" || true
    fi
    # UpCloud
    if [ -n "$UPCLOUD_TOKEN" ]; then
        [ -f "$dis/upcloud.yml" ] && mv "$dis/upcloud.yml" "$inv/upcloud.yml" || true
    else
        [ -f "$inv/upcloud.yml" ] && mv "$inv/upcloud.yml" "$dis/upcloud.yml" || true
    fi

# List available recipes
default:
    @just --list

# Initial setup: create venv, install Python deps and Galaxy collections
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d .venv ]; then
        echo "Creating Python virtual environment..."
        python3 -m venv .venv
    fi
    echo "Installing Python dependencies..."
    {{venv}}pip install -q -r requirements.txt
    echo "Installing Ansible Galaxy collections..."
    {{venv}}ansible-galaxy collection install -r requirements.yml
    echo "Done! Activate with: source .venv/bin/activate"

# Provision a new VPS (service + provider required, region optional)
provision service provider region="":
    {{venv}}ansible-playbook -i localhost, {{playbooks}}/provision.yml \
        -e target_service={{service}} \
        -e provider={{provider}} \
        {{ if region != "" { "-e region=" + region } else { "" } }}

# Deploy service to a provisioned VPS (host auto-discovered from inventory)
deploy service: sync-inventory
    {{venv}}ansible-playbook {{playbooks}}/deploy.yml \
        -e target_service={{service}}

# Provision + deploy in one step
up service provider region="":
    just provision {{service}} {{provider}} {{region}}
    just deploy {{service}}

# Destroy a VPS (provider auto-detected from saved state, or pass explicitly)
destroy service provider="":
    {{venv}}ansible-playbook -i localhost, {{playbooks}}/destroy.yml \
        -e target_service={{service}} \
        {{ if provider != "" { "-e provider=" + provider } else { "" } }}

# Redeploy: destroy + provision + deploy (new IP)
redeploy service provider region="":
    {{venv}}ansible-playbook -i localhost, {{playbooks}}/redeploy.yml \
        -e target_service={{service}} \
        -e provider={{provider}} \
        {{ if region != "" { "-e region=" + region } else { "" } }}

# Fetch credentials from a running node
creds service: sync-inventory
    {{venv}}ansible-playbook {{playbooks}}/credentials.yml \
        -e target_service={{service}}

# Show saved credentials (all instances of a service, or a specific provider)
show service provider="":
    #!/usr/bin/env bash
    if [ -n "{{provider}}" ]; then
        cat credentials/{{service}}-{{provider}}_credentials.txt 2>/dev/null || echo "No credentials for {{service}}-{{provider}}"
    else
        found=0
        for f in credentials/{{service}}-*_credentials.txt; do
            [ -f "$f" ] && { echo "=== $(basename "$f" _credentials.txt) ==="; cat "$f"; echo; found=1; }
        done
        if [ "$found" -eq 0 ]; then
            echo "No credentials found for {{service}}. Run: just up {{service}} <provider>"
        fi
    fi

# List all hosts from dynamic inventory
hosts: sync-inventory
    {{venv}}ansible-inventory --list --yaml

# List hosts for a specific service group
hosts-for service:
    {{venv}}ansible-inventory --list --yaml | grep -A5 "{{service}}:"

# Deploy everything (defaults: mtg→vultr, outline→linode)
up-all mtg_provider="vultr" outline_provider="linode":
    just up mtg {{mtg_provider}}
    just up outline {{outline_provider}}

# Destroy everything
destroy-all:
    just destroy mtg
    just destroy outline

# Redeploy everything with fresh IPs
redeploy-all mtg_provider="vultr" outline_provider="linode":
    just redeploy mtg {{mtg_provider}}
    just redeploy outline {{outline_provider}}

# Syntax check all playbooks
check:
    @for pb in provision deploy destroy redeploy credentials; do \
        echo "Checking {{playbooks}}/$pb.yml..."; \
        {{venv}}ansible-playbook --syntax-check {{playbooks}}/$pb.yml; \
    done

# Dry run a deploy (check mode)
dry-run service:
    {{venv}}ansible-playbook {{playbooks}}/deploy.yml \
        -e target_service={{service}} \
        --check --diff
