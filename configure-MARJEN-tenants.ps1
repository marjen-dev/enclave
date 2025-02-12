# Param(
#     [Parameter(Mandatory=$true)]
#     [string]$orgId,

#     [Parameter(Mandatory=$true)]
#     [string]$apiKey = ""

#     [Parameter(Mandatory=$true)]
#     [string]$gatewayname = ""
# )

#region # Connection #

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$env = "C:\repos\enclave\.env"
$apikey = get-content $env | Where-Object { $_ -match 'ENCLAVE_APIKEY' } | ForEach-Object { $_.split('=')[1] }
$orgid = get-content $env | Where-Object { $_ -match 'ENCLAVE_ORGID' } | ForEach-Object { $_.split('=')[1] }
# write-output "$apikey"
# write-output "$orgid"

if ($apiKey -eq "") {
    $apiKey = $env:ENCLAVE_API_KEY
}

if ($apiKey -eq "") {
    Write-Error "No API key provided; either specify the 'apiKey' argument, or set the ENCLAVE_API_KEY environment variable."
    return;
}

if ($orgid -eq "") {
    $orgid = $env:ENCLAVE_ORG_ID
}

if ($orgid -eq "") {
    Write-Error "No OrgID provided; either specify the 'OrgID' argument, or set the ENCLAVE_ORG_ID environment variable."
    return;
}

$headers = @{Authorization = "Bearer $apiKey" }
$contentType = "application/json";

#endregion # Connection #

#region # Invoke Enclave API #

function Invoke-EnclaveApi {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $false)]
        [object]$Body
    )

    try {
        if ($null -ne $Body) {
            return Invoke-RestMethod -ContentType $contentType -Method $Method -Uri $Uri -Headers $headers -Body ($Body | ConvertTo-Json -Depth 10)
        }
        else {
            return Invoke-RestMethod -ContentType $contentType -Method $Method -Uri $Uri -Headers $headers
        }
    } catch {
        throw "Request to $Uri failed with error: $($_.Exception.Message)"
    }
}

#endregion # Invoke Enclave API #

#region # tags #

$tags = @(
    @{
        name   = "local-ad-dns"
        colour = "#3F51B5"
    },
    @{
        name   = "internet-gateway"
        colour = "#C6FF00"
    },
    @{
        name   = "internet-gateway-user"
        colour = "#C6FF00"
    }
    @{
        name   = "internet-gateway-admin"
        colour = "#C6FF00"
    }
)

Write-Host "Evaluating Tags..."

foreach ($tag in $tags) {
    $tagsPatch = @{
        tag    = "$($tag.name)"
        colour = "$($tag.colour)"
        notes  = "$notes"
    }

    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/tags?search=$($tag.name)"

    if ($response.metadata.total -eq 0) {
        # create tag
        Write-Host "  Creating tag: $($tag.name)"
        $null = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/tags" -Body $tagsPatch
    }
    else {
        # update tag
        $tagRef = $response.items[0].ref
        Write-Host "  Refreshing tag: $($tag.name)"
        $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/tags/$tagRef" -Body $tagsPatch
    }
}

#endregion tags #

#region # Enrolment key #

Write-Host "Creating enrolment keys..."

$currentTime = (Get-Date).ToUniversalTime()

$enrolmentKeys = @(
    @{
        description   = "Gateway"
        type          = "GeneralPurpose"
        approvalMode  = "Automatic"
        notes         = "$notes"
        usesRemaining = 4
        tags          = @(
            "internet-gateway"
        )
        autoExpire    = @{
            timeZoneId     = "Etc/UTC"
            expiryDateTime = "$($currentTime.AddHours(1).ToString("yyyy-MM-ddTHH:mm"))"
            expiryAction   = "Delete"
        }
    }
)

foreach ($enrolmentKey in $enrolmentKeys) {
    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/enrolment-keys?search=$($enrolmentKey.description)"

    if ($response.metadata.total -eq 0) {
        # create enrolment key
        Write-Host "  Creating enrolment key: $($enrolmentKey.description)"
        $response = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/enrolment-keys" -Body $enrolmentKey
    }
    else {
        # update enrolment key
        # edit: no reason to update this key, it's going to automatically expire in one hour
        # $tagRef = $response.items[0].ref
        # Write-Host "  Refreshing enrolment key: $($enrolmentKey.description)"
        # $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/tags/$tagRef" -Body $tagsPatch
    }
}

#endregion # Enrolment key #

#region # dns #

Write-Host "Evaluating DNS Records..."

foreach ($dnsRecord in $("blocked", "dnsfilter")) {
    $dnsPatch = @{
        name   = "$dnsRecord"
        zoneId = 1
        notes  = "$notes"
        tags   = @("internet-gateway")
    }

    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/dns/records?hostname=$dnsRecord"

    if ($response.metadata.total -eq 0) {
        # create record
        Write-Host "  Creating DNS record: $($dnsRecord).enclave"
        $null = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/dns/records" -Body $dnsPatch
    }
    else {
        # update record
        $dnsId = $response.items[0].id
        Write-Host "  Refreshing DNS record: #$($dnsId) $($response.items[0].name).enclave"
        $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/dns/records/$dnsId" -Body $dnsPatch
    }
}

#endregion Setup dns #

#region # Trust requirements #

Write-Host "Creating trust requirements..."

$trustRequirements = @(
    @{
        description = "Geographic IP location"
        type        = "PublicIp"
        notes       = $null
        settings    = @{
            conditions    = @(
                @{ type = "country"; isBlocked = "false"; value = "US" }
            )
            configuration = @{}
        }
    }
)

foreach ($trustRequirement in $trustRequirements) {
    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/trust-requirements?search=$($trustRequirement.description)"

    if ($response.metadata.total -eq 0) {
        # Create trust requirement
        Write-Host "  Creating trust requirement: $($trustRequirement.description)"
        $response = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/trust-requirements" -Body $trustRequirement
        $trustRequirementId = $response.id
    }
    else {
        # Trust requirement already exists, handle if updates are needed
        Write-Host "  Refreshing trust requirement: $($trustRequirement.description)"
        $trustRequirementId = $response.items[0].id
        $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/trust-requirements/$trustRequirementId" -Body $trustRequirement
    }
}

#endregion # Trust requirements #

#region # systems #

Write-Host "Checking enrolled systems..."

# Search for systems enrolled using the Gateway key
$response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/systems?search=key:Gateway"

if ($response.items.Count -gt 0) {
    $gatewaySystemId = $response.items[0].systemId
    $gatewaySystemHostname = $response.items[0].hostname

    # Tag the system and enable it to act as gateway
    $systemPatch = @{
        gatewayRoutes = @(
            @{
                subnet      = "0.0.0.0/0"
                userEntered = $true
                weight      = 0
                name        = "Internet"
            }
        )
        tags          = @("internet-gateway")
    }

    Write-Host "  Refreshing system: $gatewaySystemId ($gatewaySystemHostname)"
    $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/systems/$gatewaySystemId" -Body $systemPatch
}
else {
    Write-Host "  No gateway systems enrolled"
}

#endregion # systems #

#region # Policies #

Write-Host "Configuring Policies..."
$policiesModel = @(
    @{
        type         = "General"
        description  = "(Internet Gateway) - Admin DNS Dashboard"
        isEnabled    = $true
        notes        = "$notes This policy grants administrative access to the Internet Gateway servers, be careful who you give admin access to."
        senderTags   = @(
            "internet-gateway-admin"
        )
        receiverTags = @(
            "internet-gateway"
        )
        acls         = @(
            @{
                protocol    = "Tcp"
                ports       = "80"
                description = "HTTP"
            },
            @{
                protocol    = "Tcp"
                ports       = "443"
                description = "HTTPS"
            },
            @{
                protocol    = "Tcp"
                ports       = "444"
                description = "PiHole"
            },
            @{
                protocol    = "Icmp"
                description = "PiHole"
            }
        )
    },
    @{
        type         = "General"
        description  = "(Internet Gateway) - Blocked Page"
        isEnabled    = $true
        notes        = "$notes This policy allows your users to reach the blocked page served by the Internet Gateway when DNS filtering prevents an access."
        senderTags   = @(
            "internet-gateway-user"
        )
        receiverTags = @(
            "internet-gateway"
        )
        acls         = @(
            @{
                protocol    = "Tcp"
                ports       = "80"
                description = "HTTP"
            },
            @{
                protocol    = "Tcp"
                ports       = "443"
                description = "HTTPS"
            }
        )
    },
    @{
        type         = "General"
        description  = "(Internet Gateway) - Cluster"
        isEnabled    = $true
        notes        = "$notes This policy allows your Internet Gateways to communicate and sync configurations."
        senderTags   = @(
            "internet-gateway"
        )
        receiverTags = @(
            "internet-gateway"
        )
        acls         = @(
            @{
                protocol    = "Udp"
                ports       = "53"
                description = "DNS"
            },
            @{
                protocol    = "Tcp"
                ports       = "9999"
                description = "PiHole Gravity Database Sync"
            },
            @{
                protocol    = "Icmp"
                description = "Icmp"
            }
        )
    }
    @{
        type                    = "Gateway"
        description             = "Local AD / DNS Access"
        isEnabled               = $true
        notes                   = "$notes Allows users to access AD/DNS servers in the local network."
        senderTags              = @(
            "local-ad-dns"
        )
        acls                    = @(
            @{
                protocol    = "Tcp"
                ports       = "135"
                description = "RPC Endpoint Mapper"
            },
            @{
                protocol    = "Tcp"
                ports       = "49152 - 65535"
                description = "RPC for LSA, SAM and NetLogon"
            },
            @{
                protocol    = "Tcp"
                ports       = "389"
                description = "LDAP TCP"
            },
            @{
                protocol    = "Udp"
                ports       = "389"
                description = "LDAP UDP"
            },
            @{
                protocol    = "Tcp"
                ports       = "636"
                description = "LDAP SSL"
            },
            @{
                protocol    = "Tcp"
                ports       = "3268 - 3269"
                description = "LDAP GC / SSL"
            },
            @{
                protocol    = "Tcp"
                ports       = "88"
                description = "Kerberos TCP"
            },
            @{
                protocol    = "Udp"
                ports       = "88"
                description = "Kerberos UDP"
            },
            @{
                protocol    = "Tcp"
                ports       = "464"
                description = "Kerberos Password Change TCP"
            },
            @{
                protocol    = "Udp"
                ports       = "464"
                description = "Kerberos Password Change - UDP"
            },
            @{
                protocol    = "Tcp"
                ports       = "445"
                description = "SMB"
            },
            @{
                protocol    = "Icmp"
                description = "Icmp"
            }
        )
    }
)

if ($gatewaySystemId) {
    $policiesModel[0].gateways += @{
        systemId = "$gatewaySystemId"
        routes   = @("0.0.0.0/0")
    }
}

if ($trustRequirementId) {
    $policiesModel[0] += @{
        senderTrustRequirements = @($trustRequirementId)
    }

}

# assign ender tags to policies
$policiesModel[0].senderTags += $tags[1].name, $tags[3].name
$policiesModel[3].senderTags += $tags[1].name

$response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/policies?include_disabled=true"

foreach ($policyModel in $policiesModel) {
    # tight match each returned policy against the model without relying on user configurable values like description
    $allMatchingPolicies = $response.items | Where-Object {

        $policyModelSubnets = if ($policyModel.gateways -ne $null -and $policyModel.gateways.Count -gt 0) {
            ($policyModel.gateways | ForEach-Object { $_.routes }) -join ','
        }
        else {
            $null
        }

        $apiSubnets = if ($_.gateways -ne $null -and $_.gateways.Count -gt 0) {
            ($_.gateways | ForEach-Object { $_.routes }) -join ','
        }
        else {
            $null
        }

        $typeMatch = ($_."type" -eq $policyModel.type)                                                      # match policy type
        $descriptionMatch = ($_."description" -eq $policyModel.description)                                 # match description
        $senderTagsMatch = (($_.senderTags.tag -join ',') -eq ($policyModel.senderTags -join ','))          # match sender tags
        $receiverTagsMatch = (($_.receiverTags.tag -join ',') -eq ($policyModel.receiverTags -join ','))    # match receiver tags

        # conditionally match subnets defined
        if ($policyModelSubnets -ne $null) {
            $subnetMatch = ($apiSubnets -eq $policyModelSubnets)
        }
        else {
            $subnetMatch = $true
        }

        # combine all match conditions
        $typeMatch -and
        $senderTagsMatch -and
        $receiverTagsMatch -and
        $subnetMatch -or
        $descriptionMatch
    }

    if ($null -ne $allMatchingPolicies) {
        $policyCount = @($allMatchingPolicies).Count

        if ($policyCount -ne 1) {
            Write-Host "  Multiple ($policyCount) policies found which match the definition for the '$($policyModel.description)' policy. Please review, will not alter existing policy set."

            foreach ($item in $allMatchingPolicies) {
                Write-Host "    - #$($item.id): $($item.description)"
            }
            continue
        }

        $matchedPolicy = $allMatchingPolicies[0]

        # update policy
        Write-Host "  Refreshing policy: #$($matchedPolicy.id) $($matchedPolicy.description)"
        #Write-Host $($policyModel | ConvertTo-Json -Depth 10)
        $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/policies/$($matchedPolicy.id)" -Body $policyModel
    }
    else {
        # create policy
        Write-Host "  Creating policy: $($policyModel.description)"
        $null = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/policies" -Body $policyModel
    }
}

#endregion Setup Policies #

Write-Host "Done"
