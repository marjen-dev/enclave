#!/bin/bash

set -euo pipefail

# Load environment variables
if [[ -f .env ]]; then
    while IFS='=' read -r key value; do
    case "$key" in
        ENCLAVE_API_KEY|ENCLAVE_ORG_ID)
            export "$key"="$value"
            ;;
    esac
done < <(grep -v '^#' .env | grep '=')
else
    echo "\033[0;31m[ERROR]\033[0m .env file not found"
    exit 1
fi

API_KEY=${ENCLAVE_API_KEY:-}
ORG_ID=${ENCLAVE_ORG_ID:-}
BASE_URL="https://api.enclave.io/org/$ORG_ID"
DRY_RUN=false

info()  { echo -e "\033[0;36m[INFO]\033[0m  $1"; }
success() { echo -e "\033[0;32m[OK]\033[0m    $1"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $1"; }
dryrun() { echo -e "\033[0;35m[DRY-RUN]\033[0m $1"; }

invoke_enclave_api() {
    local uri=$1
    local method=$2
    local body=${3:-}
    local url="$BASE_URL/$uri"

    if $DRY_RUN; then
        dryrun "$method $url"
        [[ -n "$body" ]] && echo "$body" | jq
        return
    fi

    if [[ -n "$body" ]]; then
        curl -s -X "$method" "$url" -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" -d "$body"
    else
        curl -s -X "$method" "$url" -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json"
    fi
}

manage_tags() {
    info "Evaluating Tags..."
    local tags=("internet-gateway" "internet-gateway-user" "internet-gateway-admin" "internet-gateway-local-ad-dns")
    for tag in "${tags[@]}"; do
        local payload=$(jq -n --arg tag "$tag" '{tag: $tag, colour: "#C6FF00"}')
        local resp=$(invoke_enclave_api "tags?search=$tag" GET)
        local total=$(echo "$resp" | jq -r '.metadata.total')
        if [[ "$total" == "0" ]]; then
            success "Creating tag: $tag"
            invoke_enclave_api "tags" POST "$payload"
        else
            local ref=$(echo "$resp" | jq -r '.items[0].ref')
            success "Refreshing tag: $tag"
            invoke_enclave_api "tags/$ref" PATCH "$payload"
        fi
    done
}

manage_enrolment_keys() {
    info "Creating enrolment keys..."
    local now=$(date -u +"%Y-%m-%dT%H:%M:00")
    local payload=$(jq -n --arg time "$now" '[{
        description: "Gateway",
        type: "GeneralPurpose",
        approvalMode: "Automatic",
        usesRemaining: 4,
        tags: ["internet-gateway"],
        autoExpire: {
            timeZoneId: "Etc/UTC",
            expiryDateTime: $time,
            expiryAction: "Delete"
        }
    }]')

    echo "$payload" | jq -c '.[]' | while read -r key; do
        local desc=$(echo "$key" | jq -r '.description')
        local resp=$(invoke_enclave_api "enrolment-keys?search=$desc" GET)
        local total=$(echo "$resp" | jq -r '.metadata.total')
        if [[ "$total" == "0" ]]; then
            success "Creating enrolment key: $desc"
            invoke_enclave_api "enrolment-keys" POST "$key"
        else
            success "Enrolment key already exists: $desc"
        fi
    done
}

manage_dns_records() {
    info "Evaluating DNS Records..."
    for dns in blocked dnsfilter; do
        local payload=$(jq -n --arg name "$dns" '{name: $name, zoneId: 1, tags: ["internet-gateway"]}')
        local resp=$(invoke_enclave_api "dns/records?hostname=$dns" GET)
        local total=$(echo "$resp" | jq -r '.metadata.total')
        if [[ "$total" == "0" ]]; then
            success "Creating DNS record: $dns.enclave"
            invoke_enclave_api "dns/records" POST "$payload"
        else
            local id=$(echo "$resp" | jq -r '.items[0].id')
            success "Refreshing DNS record: #$id $dns.enclave"
            invoke_enclave_api "dns/records/$id" PATCH "$payload"
        fi
    done
}

manage_trust_requirements() {
    info "Creating trust requirements..."
    local payload=$(jq -n '[{
        description: "US Only",
        type: "PublicIp",
        settings: {
            conditions: [{type: "country", isBlocked: false, value: "US"}],
            configuration: {}
        }
    }]')

    echo "$payload" | jq -c '.[]' | while read -r trust; do
        local desc=$(echo "$trust" | jq -r '.description')
        local resp=$(invoke_enclave_api "trust-requirements?search=$desc" GET)
        local total=$(echo "$resp" | jq -r '.metadata.total')
        if [[ "$total" == "0" ]]; then
            success "Creating trust requirement: $desc"
            invoke_enclave_api "trust-requirements" POST "$trust"
        else
            local id=$(echo "$resp" | jq -r '.items[0].id')
            success "Refreshing trust requirement: $desc"
            invoke_enclave_api "trust-requirements/$id" PATCH "$trust"
        fi
    done
}

manage_systems() {
    info "Checking enrolled systems..."
    local resp=$(invoke_enclave_api "systems?search=key:Gateway" GET)
    local count=$(echo "$resp" | jq '.items | length')

    if [[ "$count" -gt 0 ]]; then
        local id=$(echo "$resp" | jq -r '.items[0].systemId')
        local hostname=$(echo "$resp" | jq -r '.items[0].hostname')
        local payload=$(jq -n '{
            gatewayRoutes: [{subnet: "0.0.0.0/0", userEntered: true, weight: 0, name: "Internet"}],
            tags: ["internet-gateway"]
        }')
        success "Refreshing system: $id ($hostname)"
        invoke_enclave_api "systems/$id" PATCH "$payload"
    else
        warn "No gateway systems enrolled"
    fi
}

manage_policies() {
    info "Configuring Policies..."
    local policies=$(jq -n '[
        {
            type: "General",
            description: "(Internet Gateway) - Admin DNS Dashboard",
            isEnabled: true,
            notes: "Grants administrative access to Internet Gateway.",
            senderTags: ["internet-gateway-admin"],
            receiverTags: ["internet-gateway"],
            acls: [
                {protocol: "Tcp", ports: "80", description: "HTTP"},
                {protocol: "Tcp", ports: "443", description: "HTTPS"},
                {protocol: "Tcp", ports: "444", description: "PiHole"},
                {protocol: "Icmp", description: "ICMP"}
            ]
        },
        {
            type: "General",
            description: "(Internet Gateway) - Blocked Page",
            isEnabled: true,
            notes: "Allows users to access blocked page.",
            senderTags: ["internet-gateway-user"],
            receiverTags: ["internet-gateway"],
            acls: [
                {protocol: "Tcp", ports: "80", description: "HTTP"},
                {protocol: "Tcp", ports: "443", description: "HTTPS"}
            ]
        },
        {
            type: "General",
            description: "(Internet Gateway) - Cluster",
            isEnabled: true,
            notes: "Allows Internet Gateways to sync configurations.",
            senderTags: ["internet-gateway"],
            receiverTags: ["internet-gateway"],
            acls: [
                {protocol: "Udp", ports: "53", description: "DNS"},
                {protocol: "Tcp", ports: "9999", description: "PiHole Sync"},
                {protocol: "Icmp", description: "ICMP"}
            ]
        }
    ]')

    local existing=$(invoke_enclave_api "policies?include_disabled=true" GET)

    echo "$policies" | jq -c '.[]' | while read -r policy; do
        local desc=$(echo "$policy" | jq -r '.description')
        local match=$(echo "$existing" | jq --arg desc "$desc" '.items[] | select(.description == $desc)')
        if [[ -n "$match" ]]; then
            local id=$(echo "$match" | jq -r '.id')
            success "Updating policy: $desc"
            invoke_enclave_api "policies/$id" PATCH "$policy"
        else
            success "Creating policy: $desc"
            invoke_enclave_api "policies" POST "$policy"
        fi
    done
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

manage_tags
manage_enrolment_keys
manage_dns_records
manage_trust_requirements
manage_systems
manage_policies

    info "All configuration steps completed successfully."
    success "Done."
}

main "$@"
