Param(
    [Parameter(Mandatory = $true)]
    [string]$orgId,

    [Parameter(Mandatory = $true)]
    [string]$user = "",

    [Parameter(Mandatory = $true)]
    [string]$targethost = ""
)

# Use to create tags and policies to allow a user to rdp into their desktop

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

#region # Connection #

$env = "$PWD\.env"
$apikey = get-content $env | Where-Object { $_ -match 'ENCLAVE_APIKEY' } | ForEach-Object { $_.split('=')[1] }
$orgid = get-content $env | Where-Object { $_ -match 'ENCLAVE_ORGID' } | ForEach-Object { $_.split('=')[1] }

if ( $apiKey -eq "" ) {
    $apiKey = $env:ENCLAVE_API_KEY
}

if ( $apiKey -eq "" ) {
    Write-Error "No API key provided; either specify the 'apiKey' argument, or set the ENCLAVE_API_KEY environment variable."
    return;
}

if ( $orgid -eq "" ) {
    Write-Error "No OrgID provided; either specify the 'OrgID' argument, or set the ENCLAVE_ORG_ID environment variable."
    return;
}

$headers = @{ Authorization = "Bearer $apiKey" }
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
                } else {
                    throw "Request to $Uri failed with error: $($webException.Message)`nResponse Body (Non-JSON):`n$responseBody"
                }
            }
        }

        # If no response body is present, just show the exception message
        throw "Request to $Uri failed with error: $($webException.Message)"
    }
}

#endregion # Invoke Enclave API #

#region # tags #

$tags = @(
    @{
        name   = "$user-remote"
        colour = "#F0F8FE"
    }
)

Write-Host "Evaluating Tags..."

foreach ( $tag in $tags ) {
    $tagsPatch = @{
        tag    = "$($tag.name)"
        colour = "$($tag.colour)"
        notes  = "$notes"
    }

    $response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/tags?search=$($tag.name)"

    if ( $response.metadata.total -eq 0 ) {
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

#region # Policies #

Write-Host "Configuring Policies..."
$policiesModel = @(
    @{
        type        = "Gateway"
        description = "$user-rds"
        isEnabled   = $true
        notes       = "$notes Allows $user to access RDP to resources"
        senderTags  = @(
            "$user-remote"
        )
        acls        = @(
            @{
                protocol    = "Tcp"
                description = "RDP"
                port        = 3389
            }
        )
        gatewayAllowedIpRanges = @(
            @{
                gatewayAllowedIpRanges  = "$targethost"
                description             = "$user DT"
            }
        )
        # Before this i need to grab all the gateways and populate the data from the data returned?
        # gateways = @(
        #     @{
        #         systemId        = "354LG"
        #         systemName      = "(internet-gateway) - bscdalvmeg01"
        #         machineName     = "bscdalvmeg01"
        #         routes          = @(
        #             @{
        #                 route           = "192.168.1.0/24"
        #                 gatewayWeight   = 0
        #                 gatewayName     = "HQ LAN"
        #             }
        #         )
        #     }
        # )
        gatewayTrafficDirection = "Exit"
    }
)

#endregion # Setup Policies #

#region # Create Policies #

# assign sender tags to policies

$response = Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/policies?include_disabled=true"

foreach ($policyModel in $policiesModel) {
    # tight match each returned policy against the model without relying on user configurable values like description
    $allMatchingPolicies = $response.items | Where-Object {

        $policyModelSubnets = if ( $policyModel.gateways -ne $null -and $policyModel.gateways.Count -gt 0 ) {
            ( $policyModel.gateways | ForEach-Object { $_.routes } ) -join ','
        }
        else {
            $null
        }

        $apiSubnets = if ( $_.gateways -ne $null -and $_.gateways.Count -gt 0 ) {
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
        if ( $policyModelSubnets -ne $null ) {
            $subnetMatch = ( $apiSubnets -eq $policyModelSubnets )
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

    if ( $null -ne $allMatchingPolicies ) {
        $policyCount = @($allMatchingPolicies).Count

        if ( $policyCount -ne 1 ) {
            Write-Host "  Multiple ($policyCount) policies found which match the definition for the '$($policyModel.description)' policy. Please review, will not alter existing policy set."

            foreach ( $item in $allMatchingPolicies ) {
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

        Write-Host $($policyModel | ConvertTo-Json -Depth 10)

        $null = Invoke-EnclaveApi -Method Post -Uri "https://api.enclave.io/org/$orgId/policies" -Body $policyModel
    }
}

#endregion # Create Policies #

Write-Host "Done"
