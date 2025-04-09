# Setup and Management scripts for Enclave

__Note: The basis of this content came from [github](https://github.com/enclave-networks/internet-gateway)__

You will need:

- An .env file with your orgid and apikey in the following format:
      ENCLAVE_APIKEY=xxx (Enclave API key for an account with access to the tenant.)
      ENCLAVE_ORGID=yyy (Enclave tenant's organization identifier)
- At least one Linux (All my testing was with Debian 12 but Enclave recommends and supports Ubuntu 22.04 LTS (or later)) server.

The scripts in this repo are as follows:

*config-tenant.py/ps1/sh*

The basic tenant configuration script. This will include the create tags and policies scripts from below.

*config-update-policies.py/ps1/sh*

This will create or update policies (update is based on the policy name existing).

*config-update-tags.py/ps1/sh*

This will create or update tags (update is based on the tag name existing).

*docker-compose.yml*

Docker-compose file to spin up your docker instance along with watchtower to keep it updated.

*prepare-host.sh*

Striped down version of the official Enclave prepare-host.sh script.  This only creates one gateway without the entire stack (pihole, etc).

*tf_main.tf*

This is a work in progress.  Been having issues with TF.

All scripts can be customized, but a couple of things you need to know.

If you are running the python versions you will need to have requests and colorama installed in python.
All the scripts support a dry-run option. Although this would be easy enough to add.
There is no logging as everything is output in color to terminal.

```bash
./config-tenant.ps1 -dry-run
./config-tenant.py --dry-run
./config-tenant.sh --dry-run
```

__Note:__ That the `prepare-host.sh` script can be customized. By default, it prepares the OS by installing required dependencies, Docker, and Enclave. You can also enable the script to install the NetData agent, restrict SSH access for root, and enable unattended security updates.

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

__Note:__ The `config-tenant` scritps will create an Enrolment Key that's valid for one hour and two system enrollments in the target tenant which you will use to enrol each Internet Gateway:

```shell
Checking for enrolled Internet Gateways...
  No enrolled systems found in this tenant with expected hostnames of an Enclave Internet Gateway.
  Creating a new Internet Gateway Enrolment Key:

  AAAAA-AAAAA-AAAAA-AAAAA-AAAAA

  This key will automatically expire in 1 hour.
```
