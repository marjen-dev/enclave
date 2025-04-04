#!/bin/bash

# -------- Configuration -------- #

ENV_FILE=".env"

API_KEY=$(grep ENCLAVE_API_KEY "$ENV_FILE" | cut -d '=' -f2- | xargs)
ORG_ID=$(grep ENCLAVE_ORG_ID "$ENV_FILE" | cut -d '=' -f2- | xargs)

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

# -------- Configuration -------- #

# Update or create the tag based on the result
echo "Creating policy..."
curl -X 'POST' \
    "https://api.enclave.io/org/$ORG_ID/policies" \
    -H "Authorization: $API_KEY" \
    -H 'Content-Type: application/json' \
    -H 'response_headers.txt' \
    -d '{
        "type": "Gateway",
        "description": "TEST_POLICY",
        "isEnabled": true,
        "senderTags": [
            "test-rds"
        ],
        "acls": [
            {
                "protocol": "tcp",
                "ports": "443",
                "description": "test https"
            }
        ],
        "gatewayAllowedIpRanges": [
            {
                "ipRange": "0.0.0.0/0",
                "description": "user name"
            }
        ],
        "gatewayTrafficDirection": "Exit",
        "gatewayPriority": "Balanced",
        "notes": "string",
        "senderTrustRequirements": [
            1
        ]
        }'

