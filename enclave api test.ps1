
$baseurl = 'https://api.enclave.io'
$env = "c:\repos\enclave\.env"

$token = get-content $env |
    Where-Object { $_ -match 'PASS' } | ForEach-Object { $_.split('=')[1] }

function get-orgs {
     $url = $baseurl + '/account/orgs'
     curl --oauth2-bearer $token -uri $url | ConvertFrom-Json | Select-Object -Expand orgs #| Select-Object orgid
 }

 get-orgs


$orgid = get-content $env | Where-Object { $_ -match 'M_ORG' } | ForEach-Object { $_.split('=')[1] }
$url2 = $baseurl + '/org/' + $orgid + '/policies'
curl --oauth2-bearer $token -uri $url2  | ConvertFrom-Json | Select-Object -Expand items # | Select-Object systemid


{
    "type": "Gateway",
    "description": "AD / DNS",
    "isEnabled": true,
    "senderTags": [
    {
        "tag": "dns",
        "colour": "#3F51B5"
    }
    ],
    "receiverTags": [
    ],
    "acls": [
    {
        "protocol": "Tcp",
        "ports": "135",
        "description": null
    },
    {
        "protocol": "Tcp",
        "ports": "49152 - 65535",
        "description": null
    },
    {
        "protocol": "Tcp",
        "ports": "389",
        "description": ""
    },
    {
        "protocol": "Udp",
        "ports": "389",
        "description": null
    },
    {
        "protocol": "Tcp",
        "ports": "636",
        "description": null
    },
    {
        "protocol": "Tcp",
        "ports": "3268 - 3269",
        "description": null
    },
    {
        "protocol": "Tcp",
        "ports": "88",
        "description": null
    },
    {
        "protocol": "Udp",
        "ports": "88",
        "description": null
    },
    {
        "protocol": "Tcp",
        "ports": "464",
        "description": null
    },
    {
        "protocol": "Udp",
        "ports": "464",
        "description": null
    },
    {
        "protocol": "Tcp",
        "ports": "445",
        "description": null
    }
    ],
    "gatewayAllowedIpRanges": [],
    "gateways": [
    {
        "systemId": "L787D",
        "routes": [
        {
            "route": "192.168.1.0/24",
            "gatewayWeight": 0,
            "gatewayName": null
        }
        ]
    }
    ],
    "gatewayTrafficDirection": "Exit",
}
