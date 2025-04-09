import os
import json
import requests
from dotenv import load_dotenv

# ----------------------------------------
# Enclave Multi-Tag Configuration Script
# ----------------------------------------

# Load environment variables from .env file
load_dotenv()

API_KEY = os.getenv("ENCLAVE_APIKEY")
ORG_ID = os.getenv("ENCLAVE_ORGID")

# API base URL and headers
API_URL = f"https://api.enclave.io/org/{ORG_ID}"
HEADERS = {
    "Authorization": API_KEY,
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
# Define tag names and colors
# ----------------------------------------

prefix = "internet-gateway"
notes = "Auto-generated tag"

tags = [
    ("all-users", "#C6FF00"),
    (f"{prefix}", "#C6FF00"),
    (f"{prefix}-admin", "#C6FF00"),
]

# ----------------------------------------
# Process tags
# ----------------------------------------

print("Evaluating Tags...")

for tag_name, color in tags:
    tag_payload = {
        "tag": tag_name,
        "colour": color,
        "notes": notes
    }

    response = requests.get(f"{API_URL}/tags", headers=HEADERS, params={"search": tag_name})
    data = response.json()
    total = data.get("metadata", {}).get("total", 0)

    if total == 0:
        print(f"  Creating tag: {tag_name}")
        requests.post(f"{API_URL}/tags", headers=HEADERS, data=json.dumps(tag_payload))
    else:
        tag_ref = data["items"][0]["ref"]
        print(f"  Refreshing tag: {tag_name}")
        requests.patch(f"{API_URL}/tags/{tag_ref}", headers=HEADERS, data=json.dumps(tag_payload))

print("All tags processed.")

