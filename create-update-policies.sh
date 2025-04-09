#!/bin/bash

# ----------------------------------------
# Enclave Multi-Policy Configuration Script
# ----------------------------------------

ENV_FILE=".env"

API_KEY=$(grep ENCLAVE_APIKEY "$ENV_FILE" | cut -d '=' -f2- | xargs)
ORG_ID=$(grep ENCLAVE_ORGID "$ENV_FILE" | cut -d '=' -f2- | xargs)

API_URL="https://api.enclave.io/org/$ORG_ID"
HEADERS=(-H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json")

# ----------------------------------------
# Validate credentials and env.
# ----------------------------------------

if [ -z "$API_KEY" ]; then
    echo "No API key provided; set ENCLAVE_APIKEY in .env or ENCLAVE_API_KEY env var"
    exit 1
else
    echo "Setting ENCLAVE_API_KEY = $API_KEY"
fi

if [ -z "$ORG_ID" ]; then
    echo "No ORG ID provided; set ENCLAVE_ORG_ID in .env or ENCLAVE_ORG_ID env var"
    exit 1
else
    echo "Setting ENCLAVE_ORG_ID = $ORG_ID"
fi

# ----------------------------------------
# Define policies (description|tag|allowed_ip|notes)
# ----------------------------------------

declare -a policies=(
    "rds-access|internet-gateway|172.16.30.2/32|Allow RDP to remote host"
    "admin-access|internet-gateway|172.16.30.3/32|Admin access for maintenance"
    "dev-access|internet-gateway|172.16.30.0/24|Allow developers access to dev LAN"
)

# ----------------------------------------
# Process policies
# ----------------------------------------

echo "Configuring Policies..."

# Fetch all existing policies once
existing_policies=$(curl -s "${HEADERS[@]}" "$API_URL/policies?include_disabled=true")

for entry in "${policies[@]}"; do
    IFS='|' read -r description tag allowed notes <<< "$entry"

# Validate each required field
if [[ -z "$description" || -z "$tag" || -z "$allowed" || -z "$notes" ]]; then
    echo "Skipping invalid policy definition: $entry"
    continue
fi

# Build the policy JSON
policy_json=$(jq -n \
    --arg desc "$description" \
    --arg tag "$tag" \
    --arg allowed "$allowed" \
    --arg notes "$notes" \
    '{
    type: "Gateway",
    description: $desc,
    isEnabled: true,
    notes: $notes,
    senderTags: [
        $tag
    ],
    acls: [
        {
        protocol: "Any",
        description: "RDP",
        port: "Any"
        }
    ],
    "senderTrustRequirements": [
        1
    ],
    gatewayAllowedIpRanges: [
        {
        "ipRange": $allowed
        }
    ],
    gatewayTrafficDirection: "Exit"
    }')

# Check if a matching policy already exists
match=$(echo "$existing_policies" | jq --arg desc "$description" '.items[] | select(.description == $desc)')

if [[ -n "$match" ]]; then
    policy_id=$(echo "$match" | jq -r '.id')
    echo "Updating policy: #$policy_id $description"
    curl -s -X PATCH "${HEADERS[@]}" "$API_URL/policies/$policy_id" -d "$policy_json"
else
    echo "Creating policy: $description"
    curl -s -X POST "${HEADERS[@]}" "$API_URL/policies" -d "$policy_json"
fi
done

echo "All policies processed."
