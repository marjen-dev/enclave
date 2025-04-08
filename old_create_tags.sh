#!/bin/bash

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

NEW_TAG="yellow"
TAG_COLOUR="#C6FF00"

# Fetch tags from Enclave API and load into an array
tags=("$( curl -s \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    "https://api.enclave.io/org/$ORG_ID/tags?sort=Alphabetical&page=0&per_page=30" \
    | jq -r '.items[].tag' )")

# Check if the tag exists in the array
tag_exists=false
for tag in "${tags[@]}"; do
    if [[ "$tag" == "$NEW_TAG" ]]; then
        tag_exists=true
    break
    fi
done

# Update or create the tag based on the result
if [[ "$tag_exists" == true ]]; then
    echo "'$NEW_TAG' exists. Updating tag..."
    curl -X 'PATCH' \
    "https://api.enclave.io/org/$ORG_ID/tags/$NEW_TAG" \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "accept: text/plain" \
    -d '{
        "tag": "'${NEW_TAG}'",
        "colour": "'${TAG_COLOUR}'",
        "notes": "None",
        "trustRequirements": [
            1
        ]
    }'
else
    echo "Did not find '$NEW_TAG'."
    echo "Creating tag..."
    curl -X 'POST' \
        "https://api.enclave.io/org/$ORG_ID/tags" \
        -H "Authorization: $API_KEY" \
        -H "Content-Type: application/json" \
        -H "response_headers.txt" \
        -d '{
            "tag": "'${NEW_TAG}'",
            "colour": "'${TAG_COLOUR}'",
            "notes": "None",
            "trustRequirements": [
                1
            ]
        }'
fi
