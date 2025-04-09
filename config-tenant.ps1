#region # Connection #

param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$notes = "Configured by automation script"

$envPath = "$PWD\.env"
$apiKey = Get-Content $envPath | Where-Object { $_ -match 'ENCLAVE_APIKEY' } | ForEach-Object { $_.split('=')[1] }
$orgId = Get-Content $envPath | Where-Object { $_ -match 'ENCLAVE_ORGID' } | ForEach-Object { $_.split('=')[1] }

if ([string]::IsNullOrWhiteSpace($apiKey)) {
    $apiKey = $env:ENCLAVE_API_KEY
}

if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-Error "No API key provided; either specify the 'apiKey' argument, or set the ENCLAVE_API_KEY environment variable."
    return
}

if ([string]::IsNullOrWhiteSpace($orgId)) {
    $orgId = $env:ENCLAVE_ORG_ID
}

if ([string]::IsNullOrWhiteSpace($orgId)) {
    Write-Error "No OrgID provided; either specify the 'OrgID' argument, or set the ENCLAVE_ORG_ID environment variable."
    return
}

$headers = @{ Authorization = "Bearer $apiKey" }
$contentType = "application/json"

#endregion # Connection #

#region # Invoke Enclave API #

function Invoke-EnclaveApi {
    param (
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $false)][object]$Body
    )

    if ($DryRun) {
        Write-Host "[DRY-RUN] $Method $Uri"
        if ($null -ne $Body) {
            $Body | ConvertTo-Json -Depth 10 | Write-Host
        }
        return $null
    }

    try {
        if ($null -ne $Body) {
            return Invoke-RestMethod -ContentType $contentType -Method $Method -Uri $Uri -Headers $headers -Body ($Body | ConvertTo-Json -Depth 10)
        }
        else {
            return Invoke-RestMethod -ContentType $contentType -Method $Method -Uri $Uri -Headers $headers
        }
    }
    catch {
        $webException = $_.Exception
        $responseStream = $webException.Response.GetResponseStream()

        if ($responseStream) {
            $reader = New-Object System.IO.StreamReader($responseStream)
            $responseBody = $reader.ReadToEnd()

            if ($responseBody) {
                $jsonResponse = $responseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($jsonResponse) {
                    throw "Request to $Uri failed with error: $($webException.Message)`nResponse Details:`n$(ConvertTo-Json $jsonResponse -Depth 10)"
                }
                else {
                    throw "Request to $Uri failed with error: $($webException.Message)`nResponse Body (Non-JSON):`n$responseBody"
                }
            }
        }

        throw "Request to $Uri failed with error: $($webException.Message)"
    }
}

#endregion # Invoke Enclave API #

#region # Tags #

$tags = @(
    @{ name = "internet-gateway"; colour = "#C6FF00" },
    @{ name = "internet-gateway-user"; colour = "#C6FF00" },
    @{ name = "internet-gateway-admin"; colour = "#C6FF00" },
    @{ name = "internet-gateway-local-ad-dns"; colour = "#C6FF00" }
)

Write-Host "Evaluating Tags..."

foreach ($tag in $tags) {
    $tagsPatch = @{ tag = $tag.name; colour = $tag.colour; notes = $notes }
    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/tags?search=$($tag.name)"

    if ($response.metadata.total -eq 0) {
        Write-Host "  Creating tag: $($tag.name)"
        $null = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/tags" -Body $tagsPatch
    }
    else {
        $tagRef = $response.items[0].ref
        Write-Host "  Refreshing tag: $($tag.name)"
        $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/tags/$tagRef" -Body $tagsPatch
    }
}

#endregion # Tags #

#region # DNS Records #

Write-Host "Evaluating DNS Records..."

foreach ($dnsRecord in @("blocked", "dnsfilter")) {
    $dnsPatch = @{ name = $dnsRecord; zoneId = 1; notes = $notes; tags = @("internet-gateway") }
    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/dns/records?hostname=$dnsRecord"

    if ($response.metadata.total -eq 0) {
        Write-Host "  Creating DNS record: $dnsRecord.enclave"
        $null = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/dns/records" -Body $dnsPatch
    }
    else {
        $dnsId = $response.items[0].id
        Write-Host "  Refreshing DNS record: #$dnsId $($response.items[0].name).enclave"
        $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/dns/records/$dnsId" -Body $dnsPatch
    }
}

#endregion # DNS Records #

#region # Enrolment Keys #

Write-Host "Creating enrolment keys..."
$currentTime = (Get-Date).ToUniversalTime()
$expiry = $currentTime.AddHours(1).ToString("yyyy-MM-ddTHH:mm")

$enrolmentKeys = @(
    @{
        description   = "Gateway"
        type          = "GeneralPurpose"
        approvalMode  = "Automatic"
        notes         = $notes
        usesRemaining = 4
        tags          = @("internet-gateway")
        autoExpire    = @{
            timeZoneId     = "Etc/UTC"
            expiryDateTime = $expiry
            expiryAction   = "Delete"
        }
    }
)

foreach ($enrolmentKey in $enrolmentKeys) {
    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/enrolment-keys?search=$($enrolmentKey.description)"

    if ($response.metadata.total -eq 0) {
        Write-Host "  Creating enrolment key: $($enrolmentKey.description)"
        $null = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/enrolment-keys" -Body $enrolmentKey
    }
    else {
        Write-Host "  Enrolment key already exists: $($enrolmentKey.description)"
    }
}

#endregion # Enrolment Keys #

#region # Trust Requirements #

Write-Host "Creating trust requirements..."

$trustRequirements = @(
    @{
        description = "US Only"
        type        = "PublicIp"
        notes       = $null
        settings    = @{
            conditions    = @(
                @{ type = "country"; isBlocked = $false; value = "US" }
            )
            configuration = @{}
        }
    }
)

foreach ($trustRequirement in $trustRequirements) {
    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/trust-requirements?search=$($trustRequirement.description)"

    if ($response.metadata.total -eq 0) {
        Write-Host "  Creating trust requirement: $($trustRequirement.description)"
        $trustRequirementResponse = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/trust-requirements" -Body $trustRequirement
        $trustRequirementId = $trustRequirementResponse.id
    }
    else {
        Write-Host "  Refreshing trust requirement: $($trustRequirement.description)"
        $trustRequirementId = $response.items[0].id
        $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/trust-requirements/$trustRequirementId" -Body $trustRequirement
    }
}

#endregion # Trust Requirements #

#region # Systems #

Write-Host "Checking enrolled systems..."
$response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/systems?search=key:Gateway"

if ($response.items.Count -gt 0) {
    $gatewaySystemId = $response.items[0].systemId
    $gatewaySystemHostname = $response.items[0].hostname

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

#endregion # Systems #

#region # Policies #

Write-Host "Configuring Policies..."

$policiesModel = @(
    @{
        type         = "General"
        description  = "(Internet Gateway) - Admin DNS Dashboard"
        isEnabled    = $true
        notes        = $notes
        senderTags   = @("internet-gateway-admin")
        receiverTags = @("internet-gateway")
        acls         = @(
            @{ protocol = "Tcp"; ports = "80"; description = "HTTP" },
            @{ protocol = "Tcp"; ports = "443"; description = "HTTPS" },
            @{ protocol = "Tcp"; ports = "444"; description = "PiHole" },
            @{ protocol = "Icmp"; description = "ICMP" }
        )
    },
    @{
        type         = "General"
        description  = "(Internet Gateway) - Blocked Page"
        isEnabled    = $true
        notes        = $notes
        senderTags   = @("internet-gateway-user")
        receiverTags = @("internet-gateway")
        acls         = @(
            @{ protocol = "Tcp"; ports = "80"; description = "HTTP" },
            @{ protocol = "Tcp"; ports = "443"; description = "HTTPS" }
        )
    },
    @{
        type         = "General"
        description  = "(Internet Gateway) - Cluster"
        isEnabled    = $true
        notes        = $notes
        senderTags   = @("internet-gateway")
        receiverTags = @("internet-gateway")
        acls         = @(
            @{ protocol = "Udp"; ports = "53"; description = "DNS" },
            @{ protocol = "Tcp"; ports = "9999"; description = "PiHole Sync" },
            @{ protocol = "Icmp"; description = "ICMP" }
        )
    }
)

$response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/policies?include_disabled=true"

foreach ($policyModel in $policiesModel) {
    $matches = $response.items | Where-Object {
        ($_.type -eq $policyModel.type) -and
        ($_.description -eq $policyModel.description) -and
        (($_.senderTags.tag -join ',') -eq ($policyModel.senderTags -join ',')) -and
        (($_.receiverTags.tag -join ',') -eq ($policyModel.receiverTags -join ','))
    }

    if ($matches.Count -eq 1) {
        $matchedPolicy = $matches[0]
        Write-Host "  Refreshing policy: #$($matchedPolicy.id) $($matchedPolicy.description)"
        $null = Invoke-EnclaveApi -Method Patch -Uri "https://api.enclave.io/org/$orgId/policies/$($matchedPolicy.id)" -Body $policyModel
    }
    elseif ($matches.Count -eq 0) {
        Write-Host "  Creating policy: $($policyModel.description)"
        $null = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/policies" -Body $policyModel
    }
    else {
        Write-Host "  Multiple policies matched for $($policyModel.description), skipping update."
        foreach ($item in $matches) {
            Write-Host "    - #$($item.id): $($item.description)"
        }
    }
}

#endregion # Policies #
