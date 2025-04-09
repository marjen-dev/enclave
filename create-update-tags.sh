#!/bin/bash

# ----------------------------------------
# Enclave Multi-Tag Configuration Script
# ----------------------------------------

ENV_FILE=".env"

API_KEY=$(grep ENCLAVE_APIKEY "$ENV_FILE" | cut -d '=' -f2- | xargs)
ORG_ID=$(grep ENCLAVE_ORGID "$ENV_FILE" | cut -d '=' -f2- | xargs)

# API base URL
API_URL="https://api.enclave.io/org/$ORG_ID"
HEADERS=(-H "Authorization: $API_KEY" -H "Content-Type: application/json")

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
# Define tag names and colors
# ----------------------------------------

prefix="internet-gateway"
notes="Auto-generated tag"

tags=(
    "all-users:#C6FF00"
    "${prefix}:#C6FF00"
    "${prefix}-admin:#C6FF00"
)

# ----------------------------------------
# Process tags
# ----------------------------------------

echo "Evaluating Tags..."

for tag_entry in "${tags[@]}"; do
    # Split name and color
    IFS=':' read -r tag_name color <<< "$tag_entry"

    # Prepare tag JSON payload
    tag_payload=$(jq -n \
        --arg tag "$tag_name" \
        --arg color "$color" \
        --arg notes "$notes" \
        '{tag: $tag, colour: $color, notes: $notes}')

    # Check if the tag exists
    response=$(curl -s "${HEADERS[@]}" "$API_URL/tags?search=$tag_name")
    total=$(echo "$response" | jq '.metadata.total')

    if [[ "$total" -eq 0 ]]; then
        echo "  Creating tag: $tag_name"
        curl -s -X POST "${HEADERS[@]}" "$API_URL/tags" -d "$tag_payload" > /dev/null
    else
        tag_ref=$(echo "$response" | jq -r '.items[0].ref')
        echo "  Refreshing tag: $tag_name"
        curl -s -X PATCH "${HEADERS[@]}" "$API_URL/tags/$tag_ref" -d "$tag_payload" > /dev/null
    fi
done

echo "All tags processed."

