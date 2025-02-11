#!/bin/bash

set -euo pipefail

# =========================================================================

# configure script actions
DO_PREPARE_OS=true
DO_INSTALL_DOCKER=true
DO_INSTALL_ENCLAVE=true
DO_INSTALL_NETDATA=false
DO_RESTRICT_ROOT=false
DO_UNATTENDED_UPGRADES=false

# variables
NEW_HOSTNAME=""
SSH_USERNAME=""
SSH_KEY=""
NETDATA_CLOUD_CLAIM_TOKEN=""

# =========================================================================

# update
if [ "$DO_PREPARE_OS" = "true" ]; then

    echo "Updating and installing tooling ..."

    # Set noninteractive mode
    export DEBIAN_FRONTEND=noninteractive

    # Preconfigure debconf to automatically restart services without asking
    echo '* libraries/restart-without-asking boolean true' | debconf-set-selections

    apt update && apt upgrade -y
    apt install -y needrestart
    apt install -y gcc make tzdata jq iputils-ping net-tools iperf3 tcpdump telnet unzip wget screen software-properties-common gnupg speedtest-cli

    timedatectl set-ntp on
    timedatectl set-timezone UTC

    if [ -n "$NEW_HOSTNAME" ]; then

        echo "Setting new hostname to $NEW_HOSTNAME ..."

        sed -i "s/$HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
        sed -i "s/$HOSTNAME/$NEW_HOSTNAME/g" /etc/hostname
        hostname $NEW_HOSTNAME
    fi

fi

# install and configure docker
if [ "$DO_INSTALL_DOCKER" = "true" ]; then

    echo "Installing and configuring Docker ..."

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt -y update
    apt -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker

    # Configure metrics, and disable default bridge
    cat > /etc/docker/daemon.json <<EOF
{
    "metrics-addr": "127.0.0.1:9323",
    "experimental": true,
    "bridge": "none"
}
EOF

    systemctl restart docker

fi

# install enclave
if [ "$DO_INSTALL_ENCLAVE" = "true" ]; then

    curl -fsSL https://packages.enclave.io/apt/enclave.stable.gpg | gpg --dearmor -o /usr/share/keyrings/enclave.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/enclave.gpg] https://packages.enclave.io/apt stable main" | tee /etc/apt/sources.list.d/enclave.stable.list
    apt update

    apt install enclave

fi

# setup netdata
if [ "$DO_INSTALL_NETDATA" = "true" ]; then

    echo "Installing NetData Agent ..."

    if [ -z "$NETDATA_CLOUD_CLAIM_TOKEN" ]; then

        echo "Info: Cannot connect to the Netdata Cloud without a NETDATA_CLOUD_CLAIM_TOKEN. Installing locally only."
        wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh && sh /tmp/netdata-kickstart.sh --stable-channel

    else

        apt install -y netdata
        wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/kickstart.sh && sh /tmp/netdata-kickstart.sh --stable-channel --claim-token  $NETDATA_CLOUD_CLAIM_TOKEN --claim-url https://app.netdata.cloud

    fi

fi

# restrict root access to
if [ "$DO_RESTRICT_ROOT" = "true" ]; then

    if [ -z "$SSH_USERNAME" ] || [ -z "$SSH_KEY" ]; then

        echo "Error: Cannot restrict root access, USERNAME and SSH_KEY are both required."
        echo "  USERNAME: $SSH_USERNAME"
        echo "  SSH_KEY:  $SSH_KEY"

    else

        echo "Restricting root access ..."

        useradd -m -d /home/$SSH_USERNAME -s /bin/bash $SSH_USERNAME

        mkdir -p /home/$SSH_USERNAME/.ssh

        echo $SSH_KEY | tee /home/$SSH_USERNAME/.ssh/authorized_keys >/dev/null

        chown -R $SSH_USERNAME:$SSH_USERNAME /home/$SSH_USERNAME/.ssh
        chmod 700 /home/$SSH_USERNAME/.ssh
        chmod 600 /home/$SSH_USERNAME/.ssh/authorized_keys
        usermod -a -G $SSH_USERNAME

        echo "$SSH_USERNAME ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/10-$SSH_USERNAME-users > /dev/null

        # disable root ssh login
        sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config

        # restart sshd
        systemctl restart sshd

    fi

fi

# configure unattended-upgrades
if [ "$DO_UNATTENDED_UPGRADES" = "true" ]; then

    echo "Configuring unattended upgrades ..."

    # install unattended-upgrades
    apt install -y unattended-upgrades

    # accept the default option here
    dpkg-reconfigure --priority=low unattended-upgrades

    # configure unattended-upgrades
    cat <<-EOF | tee /etc/apt/apt.conf.d/50unattended-upgrades >/dev/null
// Automatically upgrade packages from these (origin:archive) pairs
//
// Note that in Ubuntu security updates may pull in new dependencies
// from non-security sources (e.g. chromium). By allowing the release
// pocket these get automatically pulled in.
Unattended-Upgrade::Allowed-Origins {
        "\${distro_id}:\${distro_codename}";
        "\${distro_id}:\${distro_codename}-security";
        // Extended Security Maintenance; doesn't necessarily exist for
        // every release and this system may not have it installed, but if
        // available, the policy for updates is such that unattended-upgrades
        // should also install from here by default.
        "\${distro_id}ESMApps:\${distro_codename}-apps-security";
        "\${distro_id}ESM:\${distro_codename}-infra-security";
//      "\${distro_id}:\${distro_codename}-updates";
//      "\${distro_id}:\${distro_codename}-proposed";
//      "\${distro_id}:\${distro_codename}-backports";
};

// This option controls whether the development release of Ubuntu will be
// upgraded automatically. Valid values are "true", "false", and "auto".
Unattended-Upgrade::DevRelease "auto";

// Never reboot automatically; we'll pull info out of the syslog to know
// if a restart is required.
Unattended-Upgrade::Automatic-Reboot "false";

// Enable logging to syslog. Default is False
Unattended-Upgrade::SyslogEnable "true";

// Verbose logging
// Unattended-Upgrade::Verbose "false";
EOF

fi
