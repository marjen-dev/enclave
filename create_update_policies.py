import os
import json
import requests
from dotenv import load_dotenv

# ----------------------------------------
# Enclave Multi-Policy Configuration Script
# ----------------------------------------

# Load .env file
load_dotenv()

API_KEY = os.getenv("ENCLAVE_API_KEY")
ORG_ID = os.getenv("ENCLAVE_ORG_ID")

API_URL = f"https://api.enclave.io/org/{ORG_ID}"
HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

# ----------------------------------------
# Validate credentials and env.
# ----------------------------------------

if not API_KEY:
    print("No API key provided; set ENCLAVE_API_KEY in .env or environment")
    exit(1)
else:
    print(f"Setting ENCLAVE_API_KEY = {API_KEY}")

if not ORG_ID:
    print("No ORG ID provided; set ENCLAVE_ORG_ID in .env or environment")
    exit(1)
else:
    print(f"Setting ENCLAVE_ORG_ID = {ORG_ID}")

# ----------------------------------------
# Define policies (description|tag|allowed_ip|notes)
# ----------------------------------------

policies = [
    "rds-access|internet-gateway|172.16.30.2/32|Allow RDP to remote host",
    "admin-access|internet-gateway|172.16.30.3/32|Admin access for maintenance",
    "dev-access|internet-gateway|172.16.30.0/24|Allow developers access to dev LAN"
]

# ----------------------------------------
# Process policies
# ----------------------------------------

print("Configuring Policies...")

# Fetch all existing policies once
existing_response = requests.get(f"{API_URL}/policies", headers=HEADERS, params={"include_disabled": "true"})
existing_policies = existing_response.json().get("items", [])

for entry in policies:
    try:
        description, tag, allowed, notes = entry.split("|")
    except ValueError:
        print(f"Skipping invalid policy definition: {entry}")
        continue

    # Build policy payload
    policy_payload = {
        "type": "Gateway",
        "description": description,
        "isEnabled": True,
        "notes": notes,
        "senderTags": [tag],
        "acls": [{
            "protocol": "Any",
            "description": "RDP",
            "port": "Any"
        }],
        "senderTrustRequirements": [1],
        "gatewayAllowedIpRanges": [{
            "ipRange": allowed
        }],
        "gatewayTrafficDirection": "Exit"
    }

    # Check for existing policy by description
    match = next((p for p in existing_policies if p["description"] == description), None)

    if match:
        policy_id = match["id"]
        print(f"Updating policy: #{policy_id} {description}")
        requests.patch(f"{API_URL}/policies/{policy_id}", headers=HEADERS, data=json.dumps(policy_payload))
    else:
        print(f"Creating policy: {description}")
        requests.post(f"{API_URL}/policies", headers=HEADERS, data=json.dumps(policy_payload))

print("All policies processed.")
