import os
import json
import requests
from datetime import datetime, timedelta
from dotenv import load_dotenv
from colorama import init, Fore, Style

init(autoreset=True)

load_dotenv()

API_KEY = os.getenv("ENCLAVE_API_KEY")
ORG_ID = os.getenv("ENCLAVE_ORG_ID")
BASE_URL = f"https://api.enclave.io/org/{ORG_ID}"
HEADERS = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}

def info(msg):
    print(f"{Fore.CYAN}[INFO]{Style.RESET_ALL} {msg}")

def success(msg):
    print(f"{Fore.GREEN}[OK]{Style.RESET_ALL} {msg}")

def warn(msg):
    print(f"{Fore.YELLOW}[WARN]{Style.RESET_ALL} {msg}")

def dryrun(msg):
    print(f"{Fore.MAGENTA}[DRY-RUN]{Style.RESET_ALL} {msg}")

def invoke_enclave_api(uri, method, body=None, dry_run=False):
    url = f"{BASE_URL}/{uri}"
    if dry_run:
        dryrun(f"{method} {url}")
        if body:
            print(json.dumps(body, indent=5))
        return {}
    response = requests.request(method, url, headers=HEADERS, json=body)
    response.raise_for_status()
    return response.json() if response.content else {}

def manage_tags(dry_run=False):
    tags = [
        {"name": "internet-gateway", "colour": "#C6FF00"},
        {"name": "internet-gateway-user", "colour": "#C6FF00"},
        {"name": "internet-gateway-admin", "colour": "#C6FF00"},
        {"name": "internet-gateway-local-ad-dns", "colour": "#C6FF00"}
    ]
    info("Evaluating Tags...")
    for tag in tags:
        tag_name = tag["name"]
        payload = {"tag": tag_name, "colour": tag["colour"]}
        response = invoke_enclave_api(f"tags?search={tag_name}", "GET")
        if response.get("metadata", {}).get("total", 0) == 0:
            success(f"Creating tag: {tag_name}")
            invoke_enclave_api("tags", "POST", payload, dry_run)
        else:
            tag_ref = response["items"][0]["ref"]
            success(f"Refreshing tag: {tag_name}")
            invoke_enclave_api(f"tags/{tag_ref}", "PATCH", payload, dry_run)

def manage_enrolment_keys(dry_run=False):
    now = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:00")
    keys = [
        {
            "description": "Gateway",
            "type": "GeneralPurpose",
            "approvalMode": "Automatic",
            "usesRemaining": 4,
            "tags": ["internet-gateway"],
            "autoExpire": {
                "timeZoneId": "Etc/UTC",
                "expiryDateTime": now,
                "expiryAction": "Delete"
            }
        }
    ]
    info("Creating enrolment keys...")
    for key in keys:
        desc = key["description"]
        response = invoke_enclave_api(f"enrolment-keys?search={desc}", "GET")
        if response.get("metadata", {}).get("total", 0) == 0:
            success(f"Creating enrolment key: {desc}")
            invoke_enclave_api("enrolment-keys", "POST", key, dry_run)
        else:
            success(f"Enrolment key already exists: {desc}")

def manage_dns_records(dry_run=False):
    dns_records = ["blocked", "dnsfilter"]
    info("Evaluating DNS Records...")
    for dns in dns_records:
        payload = {
            "name": dns,
            "zoneId": 1,
            "tags": ["internet-gateway"]
        }
        response = invoke_enclave_api(f"dns/records?hostname={dns}", "GET")
        if response.get("metadata", {}).get("total", 0) == 0:
            success(f"Creating DNS record: {dns}.enclave")
            invoke_enclave_api("dns/records", "POST", payload, dry_run)
        else:
            record_id = response["items"][0]["id"]
            success(f"Refreshing DNS record: #{record_id} {dns}.enclave")
            invoke_enclave_api(f"dns/records/{record_id}", "PATCH", payload, dry_run)

def manage_trust_requirements(dry_run=False):
    trust_reqs = [
        {
            "description": "US Only",
            "type": "PublicIp",
            "settings": {
                "conditions": [
                    {"type": "country", "isBlocked": False, "value": "US"}
                ],
                "configuration": {}
            }
        }
    ]
    info("Creating trust requirements...")
    for trust in trust_reqs:
        desc = trust["description"]
        response = invoke_enclave_api(f"trust-requirements?search={desc}", "GET")
        if response.get("metadata", {}).get("total", 0) == 0:
            success(f"Creating trust requirement: {desc}")
            invoke_enclave_api("trust-requirements", "POST", trust, dry_run)
        else:
            trust_id = response["items"][0]["id"]
            success(f"Refreshing trust requirement: {desc}")
            invoke_enclave_api(f"trust-requirements/{trust_id}", "PATCH", trust, dry_run)

def manage_systems(dry_run=False):
    info("Checking enrolled systems...")
    response = invoke_enclave_api("systems?search=key:Gateway", "GET")
    items = response.get("items", [])
    if items:
        gateway_id = items[0]["systemId"]
        hostname = items[0]["hostname"]
        patch = {
            "gatewayRoutes": [
                {
                    "subnet": "0.0.0.0/0",
                    "userEntered": True,
                    "weight": 0,
                    "name": "Internet"
                }
            ],
            "tags": ["internet-gateway"]
        }
        success(f"Refreshing system: {gateway_id} ({hostname})")
        invoke_enclave_api(f"systems/{gateway_id}", "PATCH", patch, dry_run)
    else:
        warn("No gateway systems enrolled")

def manage_policies(dry_run=False):
    info("Configuring Policies...")
    policies = [
        {
            "type": "General",
            "description": "(Internet Gateway) - Admin DNS Dashboard",
            "isEnabled": True,
            "notes": "Grants administrative access to Internet Gateway.",
            "senderTags": ["internet-gateway-admin"],
            "receiverTags": ["internet-gateway"],
            "acls": [
                {"protocol": "Tcp", "ports": "80", "description": "HTTP"},
                {"protocol": "Tcp", "ports": "443", "description": "HTTPS"},
                {"protocol": "Tcp", "ports": "444", "description": "PiHole"},
                {"protocol": "Icmp", "description": "ICMP"}
            ]
        },
        {
            "type": "General",
            "description": "(Internet Gateway) - Blocked Page",
            "isEnabled": True,
            "notes": "Allows users to access blocked page.",
            "senderTags": ["internet-gateway-user"],
            "receiverTags": ["internet-gateway"],
            "acls": [
                {"protocol": "Tcp", "ports": "80", "description": "HTTP"},
                {"protocol": "Tcp", "ports": "443", "description": "HTTPS"}
            ]
        },
        {
            "type": "General",
            "description": "(Internet Gateway) - Cluster",
            "isEnabled": True,
            "notes": "Allows Internet Gateways to sync configurations.",
            "senderTags": ["internet-gateway"],
            "receiverTags": ["internet-gateway"],
            "acls": [
                {"protocol": "Udp", "ports": "53", "description": "DNS"},
                {"protocol": "Tcp", "ports": "9999", "description": "PiHole Sync"},
                {"protocol": "Icmp", "description": "ICMP"}
            ]
        }
    ]

    response = invoke_enclave_api("policies?include_disabled=true", "GET")
    existing = response.get("items", [])

    for policy in policies:
        matched = [p for p in existing if p["description"] == policy["description"]]

        if len(matched) == 1:
            policy_id = matched[0]["id"]
            success(f"Updating policy: {policy['description']}")
            invoke_enclave_api(f"policies/{policy_id}", "PATCH", policy, dry_run)
        elif len(matched) == 0:
            success(f"Creating policy: {policy['description']}")
            invoke_enclave_api("policies", "POST", policy, dry_run)
        else:
            warn(f"Skipping policy: {policy['description']} (multiple matches found)")



def main():
    import argparse
    parser = argparse.ArgumentParser(description="Configure Enclave environment")
    parser.add_argument("--dry-run", action="store_true", help="Print actions without executing")
    args = parser.parse_args()

    manage_tags(dry_run=args.dry_run)
    manage_enrolment_keys(dry_run=args.dry_run)
    manage_dns_records(dry_run=args.dry_run)
    manage_trust_requirements(dry_run=args.dry_run)
    manage_systems(dry_run=args.dry_run)
    manage_policies(dry_run=args.dry_run)

    info("All configuration steps completed successfully.")
    success("Done.")

if __name__ == "__main__":
    main()
