# Param(
#     [Parameter(Mandatory=$true)]
#     [string]$orgId,

#     [Parameter(Mandatory=$true)]
#     [string]$apiKey = ""

#     [Parameter(Mandatory=$true)]
#     [string]$gatewayname = ""

# )

#region Connection #

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$gatewayname = "deb3000"
$apikey = get-content $env | Where-Object { $_ -match 'ENCLAVE_APIKEY' } | ForEach-Object { $_.split('=')[1] }
$orgid = get-content $env | Where-Object { $_ -match 'ENCLAVE_ORGID' } | ForEach-Object { $_.split('=')[1] }

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

$HasPrimaryGateway = $false
$HasSecondaryGateway = $false
$HasEnrolledGateways = $false

$GatewayHostnamePrimary = $gatewayname
$GatewayHostnameSecondary = "gateway-secondary"

$systemIdPrimary = ""
$systemIdSecondary = "";

$currentDateTime = Get-Date -Format "yyyy-MM-dd"
$notes = "Internet Gateway resource auto-provisioned by API on $currentDateTime, do not delete."

$headers = @{Authorization = "Bearer $apiKey" }
$contentType = "application/json";

#endregion Connection #

#region Invoke Enclave API #

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
    }
    catch {
        throw "Request to $Uri failed with error: $($_.Exception.Message)"
    }
}

#endregion Invoke Enclave API #

#region Check for enrolment key #

Write-Host "Checking for enrolled Internet Gateways..."

foreach ($system in @($GatewayHostnamePrimary, $GatewayHostnameSecondary)) {
    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/systems?search=$system"

    if ($response.items.Count -gt 0) {

        $HasEnrolledGateways = $true

        if ($system -eq $GatewayHostnamePrimary) {
            $HasPrimaryGateway = $true
        }
        elseif ($system -eq $GatewayHostnameSecondary) {
            $HasSecondaryGateway = $true
        }
    }
}

if ($HasEnrolledGateways -eq $false) {
    Write-Host "  No enrolled systems found in this tenant with expected hostnames of an Enclave Internet Gateway."
    Write-Host "  Creating a new Internet Gateway Enrolment Key:"
    Write-Host ""

    $currentTime = (Get-Date).ToUniversalTime()

    $enrolmentKeyPatch = @{
        description   = "Internet Gateway"
        type          = "GeneralPurpose"
        approvalMode  = "Automatic"
        notes         = "$notes"
        usesRemaining = 2
        tags          = @(
            "internet-gateway"
        )
        autoExpire    = @{
            timeZoneId     = "Etc/UTC"
            expiryDateTime = "$($currentTime.AddHours(1).ToString("yyyy-MM-ddTHH:mm"))"
            expiryAction   = "Delete"
        }
    }

    # create enrolment key
    $response = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/enrolment-keys" -Body $enrolmentKeyPatch

    Write-Host "  $($response.key)"
    Write-Host ""
    Write-Host "  This key will automatically expire in 1 hour."
    Write-Host ""

    exit 0
}

#endregion Check for enrolment key #

#region Setup tags #

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

#endregion Setup tags #

#region Setup dns #

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

#region Setup Systems #
Write-Host "Evaluating Systems..."
foreach ($system in @($GatewayHostnamePrimary, $GatewayHostnameSecondary)) {
    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/systems?search=$system"

    if ($response.items.Count -eq 0) {
        continue
    }

    $systemId = $response.items[0].systemId;

    # enable system to act as gateway
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

    Write-Host "  Refreshing system: $systemId ($system)"
    $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/systems/$systemId" -Body $systemPatch

    if ($system -eq $GatewayHostnamePrimary) {
        $systemIdPrimary = $systemId
    }
    elseif ($system -eq $GatewayHostnameSecondary) {
        $systemIdSecondary = $systemId
    }
}

#endregion Setup Systems #

#region Setup Policies #

Write-Host "Evaluating Policies..."
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
        notes        = "$notes This policy allows your Internet Gateways to communicate and syncronise configuration."
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
)
if ($HasEnrolledGateways -eq $true) {
    $policiesModel += @{
        type                    = "Gateway"
        description             = "Local AD / DNS Access"
        isEnabled               = $true
        notes                   = "$notes"
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
        gateways                = @()
        gatewayTrafficDirection = "Exit"
        gatewayAllowedIpRanges  = @()
        gatewayPriority         = "Balanced"
    }
}

if ($HasPrimaryGateway -eq $true) {
    $policiesModel[3].gateways += @{
        systemId = "$systemIdPrimary"
        routes   = @("0.0.0.0/0")
    }
}

if ($HasSecondaryGateway -eq $true) {
    $policiesModel[3].gateways += @{
        systemId = "$systemIdSecondary"
        routes   = @("0.0.0.0/0")
    }
}

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
