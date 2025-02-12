# Enclave Internet Gateway

You will need:

- An Enclave API key for an account with access to the tenant.
- The Enclave tenant's organization identifier.
- At least one Ubuntu 22.04 LTS (or later) server.

## Prepare the host

1. Clone this repository

    ```bash
    git clone https://github.com/enclave-networks/internet-gateway.git
    ```

1. Install Enclave, Docker, and other dependencies

    ```bash
    cd internet-gateway/
    chmod +x *.sh
    sudo ./prepare-host.sh
    ```

Note that the `prepare-host.sh` script can be customized. By default, it prepares the OS by installing required dependencies, Docker, and Enclave. You can also enable the script to install the NetData agent, restrict SSH access for root, and enable unattended security updates.

```bash
DO_PREPARE_OS=true
DO_INSTALL_DOCKER=true
DO_INSTALL_ENCLAVE=true
DO_INSTALL_NETDATA=false
DO_RESTRICT_ROOT=false
DO_UNATTENDED_UPGRADES=false
```

For example;

```shell
NEW_HOSTNAME="DC2-UBUNTU-12"
SSH_USERNAME="gateway-admin"
SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK0wmN/Cr3JXqmLW7u+g9pTh+wyqDHpSQEIQczXkVx9q hello@example.com"
NETDATA_CLOUD_CLAIM_TOKEN=""
```

## Provision a new Internet Gateway

Steps to provision a new set of Internet Gateways.

### 1. Create an Enrolment Key

On Windows, run `configure-tenant.ps1` passing in your `orgId` and `apiKey`.

```shell
.\configure-tenant.ps1 -orgId abcdefghijklmnopqrstuvwxyz012345 -apiKey abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0
```

The PowerShell script will create an Enrolment Key that's valid for one hour and two system enrollments in the target tenant which you will use to enrol each Internet Gateway:

```shell
Checking for enrolled Internet Gateways...
  No enrolled systems found in this tenant with expected hostnames of an Enclave Internet Gateway.
  Creating a new Internet Gateway Enrolment Key:

  AAAAA-AAAAA-AAAAA-AAAAA-AAAAA

  This key will automatically expire in 1 hour.
```

### 2. Generate a new Internet Gateway Docker stack

On your Ubuntu server, we'll now use the Enrolment Key from step 1 to create a Docker stack for the primary and secondary Internet Gateways.

In this example our Internet Gateways are going to be for "Acme Labs", this name will be used as the directory name where the `docker-compose.yml` files will be built for each Internet Gateway in this stack:

```shell
sudo ./generate-stack.sh -c "ACME Labs" -g -k AAAAA-AAAAA-AAAAA-AAAAA-AAAAA
```

The `-g` argument tells the script to generate a new Trusted Root Certificate Authority for this stack, and `-k` passes the enrolment key so the Enclave container in each stack can enrol to the tenant.

Expect to see output that looks like this:

```shell
CUSTOMER_NAME:                    ACME Labs
STACK_PATH:                       ./stacks/acme_labs
PKI_PATH:                         ./stacks/acme_labs/pki
PRIMARY_PATH:                     ./stacks/acme_labs/primary-gateway
SECONDARY_PATH:                   ./stacks/acme_labs/secondary-gateway
ENCLAVE_ENROLMENT_KEY:            AAAAA-AAAAA-AAAAA-AAAAA-AAAAA
CA_COMMON_NAME:                   Enclave Internet Gateway Authority (ACME Labs)
ENCLAVE_LOCAL_PORT_ON_PRIMARY:    40000
ENCLAVE_LOCAL_PORT_ON_SECONDARY:  40001
DOCKER_BRIDGE_NAME:               rarlx656iq_n
```

Both the primary and secondary Docker stacks for each Internet Gateway have been built in the `./stacks/acme_labs` directory.

Note that each stack directory contains a copy of the **public** Trusted Root Certificate Authority certificate `gateway.crt`, and it's corresponding **private** `gateway.key` file. Only the Docker stack needs access to the private key file. The public certificate will need to be downloaded and installed into the `Trusted Root Certification Authorities` of the `Local Machine` for end-users.

If you generated the stack locally, move each stack directory to it's correct location, or server now. We recommend separate hardware for each Internet Gateway, but it's perfectly possible to run both stacks on the same host OS.

- Primary Internet Gateway: `./stacks/acme_labs/primary-gateway`
- Secondary Internet Gateway: `./stacks/acme_labs/secondary-gateway`

### 3. Deploy the stack(s)

The first time you deploy a new stack, you should run the `initialise-bridge-network.sh` file on each host server to setup iptables and the docker network bridge network:

```bash
user@DC2-UBUNTU-12:~$ cd stacks/acme_labs/primary-gateway/
user@DC2-UBUNTU-12:~/stacks/acme_labs/primary-gateway$ chmod +x initialise-bridge-network.sh
user@DC2-UBUNTU-12:~/stacks/acme_labs/primary-gateway$ sudo ./initialise-bridge-network.sh
```

Expect to see output similar to:

```shell
441138f7c4499a18f611c14a4968f0f91aa5ccfedeb42a05aebb57ca7447fc58
Adding iptables rule to allow the bridge network to snat to the Internet
```

If you run the script a second time, expect to see output similar to:

```shell
docker bridge network uwhzjej7gw_n for this stack already exists, nothing to do.
iptables snat rule 172.17.0.0/16 for this stack already exists, nothing to do.
```

Now we can ask Docker to bring the primary gateway online:

```bash
sudo docker compose up -d --pull always
```

Repeat this step for the secondary Internet Gateway, so that both Internet Gateways enrolled and show as online in the Enclave Portal before proceeding.

### 4. Configure Internet Gateway policies in the Enclave Tenant

Back in your Windows environment, the same script from step 1, `configure-tenant.ps1` can now be run a second time. As before, pass the same `orgId` and `apiKey`.

This time, the script will detect the presence of the newly enrolled Internet Gateways and instead of generating an enrolment key, it will configure the required Tags, Policies and DNS Records in the tenant to enable the Internet Gateways to function as intended.

```shell
.\configure-tenant.ps1 -orgId abcdefghijklmnopqrstuvwxyz012345 -apiKey abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0
```

Expect to see output similar to:

```shell
Checking for enrolled Internet Gateways...
Evaluating Tags...
  Refreshing tag: internet-gateway
  Creating tag: internet-gateway-admin
  Creating tag: internet-gateway-user
Evaluating DNS Records...
  Creating DNS record: blocked.enclave
  Creating DNS record: dnsfilter.enclave
Evaluating Systems...
  Refreshing system: QW448 (gateway-primary)
  Refreshing system: 4WXXW (gateway-secondary)
Evaluating Policies...
  Creating policy: (Internet Gateway) - Admin DNS Dashboard
  Creating policy: (Internet Gateway) - Blocked Page
  Creating policy: (Internet Gateway) - Cluster
  Creating policy: (Internet Gateway) - Internet Access
Done
```

If changes are accidentally made to any of these policies in the future, running the `configure-tenant.ps1` script again will attempt to automatically detect the drift and refresh the correct configuration into the tenant.

## Testing and installing root certificate

There are three new Tags in the tenant:

- `[internet-gateway]` - Applied to the Internet Gateways themselves.
- `[internet-gateway-user]` - Should be applied to end-users.
- `[internet-gateway-admin]` - A special tag for Internet Gateway administrators only.

Enrol yourself to the tenant and attach the `[internet-gateway-admin]` tag to your system. You'll now be able to access [http://dnsfilter.enclave](http://dnsfilter.enclave) - the PiHole administration interface.

We recommend downloading and installing the Gateway's Root Certificate so your browser can trust the block page ([https://blocked.enclave/](https://blocked.enclave/)).

Download the Internet Gateway CA's public certificate in the appropriate format for yourself and end-users:

- <http://dnsfilter.enclave/gateway.crt>
- <http://dnsfilter.enclave/gateway.p7b>

On Windows, use the `certmgr` tool to install `gateway.crt` into the `Trusted Root Certification Authorities` store using the `LOCAL COMPUTER` scope and restart your browser. Navigate to [http://dnsfilter.enclave](http://dnsfilter.enclave) and check you don't receive any certificate warnings.

To test if your network traffic is successfully routing through the Internet Gateway, check your external IP address and then apply the `[internet-gateway-user]` tag to your system. Your Internet traffic should now be routing through the Internet Gateways and your external IP address should have changed to present as that of the primary Internet Gateway.

## Advanced

### Operational notes

- Failover between gateways is automatic. If one fails or goes offline, connected systems will automatically switch.
- You may need to disable `Use secure DNS` in Chrome (`chrome://settings/security`) to stop it sending DNS queries directly to Google nameservers.
- Notice the `300M` docker [memory limit](https://github.com/enclave-networks/internet-gateway/blob/main/template/docker-compose.primary.yml#L13) applied to the Enclave container and increase as required.
- Only make PiHole configuration changes on the _primary_ gateway as the PiHole configuration in [synced](https://github.com/enclave-networks/internet-gateway/blob/main/template/docker-compose.primary.yml#L124) _from_ the primary to the secondary every 30 minutes.

### Inspection

To inspect the running environment, the docker commands `ps`, `exec`, `stats` and `logs` can be helpful.

To inspect iptables snat run:

```bash
sudo iptables -t nat -L POSTROUTING -v -n
```

### Uninstall

!!! Warning: Read these commands **BEFORE** you run them. If you don't understand exactly what they will do, contact us on our support channels for assistance.

```bash
sudo docker stop $(sudo docker ps -q) && sudo docker rm $(sudo docker ps -aq)
sudo docker network rm $(sudo docker network ls -q)
sudo docker volume rm $(docker volume ls -qf dangling=true)
sudo iptables -t nat -S POSTROUTING | grep "_n" | sed 's/^-A /-D /' | while read -r line; do sudo iptables -t nat $line; done
sudo rm -rf ./stacks/
```
