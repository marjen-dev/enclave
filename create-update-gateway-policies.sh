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
    "all-users - Local AD / DNS Access|internet-gateway|all-users|Allow RDP to remote host"
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
            "protocol": "Tcp",
            "ports": "135",
            "description": null
        },
        {
            "protocol": "Tcp",
            "ports": "49152 - 65535",
            "description": null
        },
        {
            "protocol": "Tcp",
            "ports": "389",
            "description": ""
        },
        {
            "protocol": "Udp",
            "ports": "389",
            "description": null
        },
        {
            "protocol": "Tcp",
            "ports": "636",
            "description": null
        },
        {
            "protocol": "Tcp",
            "ports": "3268 - 3269",
            "description": null
        },
        {
            "protocol": "Tcp",
            "ports": "88",
            "description": null
        },
        {
            "protocol": "Udp",
            "ports": "88",
            "description": null
        },
        {
            "protocol": "Tcp",
            "ports": "464",
            "description": null
        },
        {
            "protocol": "Udp",
            "ports": "464",
            "description": null
        },
        {
            "protocol": "Tcp",
            "ports": "445",
            "description": null
        }
    ],
    senderTrustRequirements: [
        1
    ],
    gatewayAllowedIpRanges: [
        {
            "ipRange": $allowed
        }
    ],
    "gatewayAllowedIpRanges": [],
    "gateways": [
        {
            "systemId": "L787D",
            "systemName": "(internet-gateway) - LCA-LEG01",
            "machineName": "LCA-LEG01",
            "routes": [
                {
                    "route": "192.168.1.0/24",
                    "gatewayWeight": 0,
                    "gatewayName": null
                }
            ]
        }
    ],
    "gatewayTrafficDirection": "Exit",
    "notes": "Allows users to access AD/DNS servers in the local network."
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

