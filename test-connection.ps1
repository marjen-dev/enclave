#region # Connection #



$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$env = "$PWD\.env"
$apikey = get-content $env | Where-Object { $_ -match 'ENCLAVE_APIKEY' } | ForEach-Object { $_.split('=')[1] }
$orgid = get-content $env | Where-Object { $_ -match 'ENCLAVE_ORGID' } | ForEach-Object { $_.split('=')[1] }
# write-output "$apikey"
# write-output "$orgid"

if ( $apiKey -eq "" ) {
    $apiKey = $env:ENCLAVE_API_KEY
}

if ( $apiKey -eq "" ) {
    Write-Error "No API key provided; either specify the 'apiKey' argument, or set the ENCLAVE_API_KEY environment variable."
    return;
}

if ( $orgid -eq "" ) {
    $orgid = $env:ENCLAVE_ORG_ID
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
                }
                else {
                    throw "Request to $Uri failed with error: $($webException.Message)`nResponse Body (Non-JSON):`n$responseBody"
                }
            }
        }

        # If no response body is present, just show the exception message
        throw "Request to $Uri failed with error: $($webException.Message)"
    }
}

#endregion # Invoke Enclave API #

# Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/account/orgs"
Invoke-EnclaveApi -Method Get -Uri "https://api.enclave.io/org/$orgId/tags?search=fileserver"

# curl -X 'GET' 'https://api.enclave.io/account/orgs' -H 'accept: text/plain' -H 'Authorization: dx25BgHzu1ZQ8DVpdSfHqHSAYkhwrUHJztDZpvvvSBbYSTq41W3YR5S5gbX6HF6'
