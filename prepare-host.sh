#!/bin/bash

set -euo pipefail

# =========================================================================

# configure script actions
DO_PREPARE_OS=true
DO_INSTALL_ENCLAVE=true
DO_RESTRICT_ROOT=false
DO_UNATTENDED_UPGRADES=true

# variables
NEW_HOSTNAME=""
SSH_USERNAME=""
SSH_PASSWD=""
SSH_KEY=""
export ENCLAVE_ENROLMENT_KEY=xxxxx-xxxxx-xxxxx-xxxxx-xxxxx

# =========================================================================

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# update
if [ "$DO_PREPARE_OS" = "true" ]; then

    echo "Updating and installing tooling ..."

    # Set noninteractive mode
    export DEBIAN_FRONTEND=noninteractive

    # Pre-configure debconf to automatically restart services without asking
    echo '* libraries/restart-without-asking boolean true' | debconf-set-selections

    apt update && apt upgrade -y
    apt install -y needrestart
    apt install -y gcc make tzdata jq iputils-ping net-tools iperf3 tcpdump telnet unzip wget screen software-properties-common gnupg speedtest-cli openssh-server gpg curl apt-transport-https

    # timedatectl set-ntp on
    # timedatectl set-timezone CST

    # systemctl enable ssh
    # systemctl start ssh

    if [ -n "$NEW_HOSTNAME" ]; then

        echo "Setting new hostname to $NEW_HOSTNAME ..."

        sed -i "s/$HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
        sed -i "s/$HOSTNAME/$NEW_HOSTNAME/g" /etc/hostname
        hostname $NEW_HOSTNAME
    fi
fi

# install enclave
if [ "$DO_INSTALL_ENCLAVE" = "true" ]; then

    curl -fsSL https://packages.enclave.io/apt/enclave.stable.gpg | gpg --dearmor -o /usr/share/keyrings/enclave.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/enclave.gpg] https://packages.enclave.io/apt stable main" | tee /etc/apt/sources.list.d/enclave.stable.list
    apt update

    apt install enclave
    enclave enrol
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
// Unattended-Upgrade::Origins-Pattern controls which packages are
// upgraded.
//
// Lines below have the format "keyword=value,...".  A
// package will be upgraded only if the values in its metadata match
// all the supplied keywords in a line.  (In other words, omitted
// keywords are wild cards.) The keywords originate from the Release
// file, but several aliases are accepted.  The accepted keywords are:
//   a,archive,suite (eg, "stable")
//   c,component     (eg, "main", "contrib", "non-free")
//   l,label         (eg, "Debian", "Debian-Security")
//   o,origin        (eg, "Debian", "Unofficial Multimedia Packages")
//   n,codename      (eg, "jessie", "jessie-updates")
//     site          (eg, "http.debian.net")
// The available values on the system are printed by the command
// "apt-cache policy", and can be debugged by running
// "unattended-upgrades -d" and looking at the log file.
//
// Within lines unattended-upgrades allows 2 macros whose values are
// derived from /etc/debian_version:
//   ${distro_id}            Installed origin.
//   ${distro_codename}      Installed codename (eg, "buster")
Unattended-Upgrade::Origins-Pattern {
        // Codename based matching:
        // This will follow the migration of a release through different
        // archives (e.g. from testing to stable and later oldstable).
        // Software will be the latest available for the named release,
        // but the Debian release itself will not be automatically upgraded.
//      "origin=Debian,codename=${distro_codename}-updates";
//      "origin=Debian,codename=${distro_codename}-proposed-updates";
        "origin=Debian,codename=${distro_codename},label=Debian";
        "origin=Debian,codename=${distro_codename},label=Debian-Security";
        "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
        "origin=Enclave,archive=stable";
        // Archive or Suite based matching:
        // Note that this will silently match a different release after
        // migration to the specified archive (e.g. testing becomes the
        // new stable).
//      "o=Debian,a=stable";
//      "o=Debian,a=stable-updates";
//      "o=Debian,a=proposed-updates";
//      "o=Debian Backports,a=${distro_codename}-backports,l=Debian Backports";
};

// Python regular expressions, matching packages to exclude from upgrading
Unattended-Upgrade::Package-Blacklist {
    // The following matches all packages starting with linux-
//  "linux-";

    // Use $ to explicitly define the end of a package name. Without
    // the $, "libc6" would match all of them.
//  "libc6$";
//  "libc6-dev$";
//  "libc6-i686$";

    // Special characters need escaping
//  "libstdc\+\+6$";

    // The following matches packages like xen-system-amd64, xen-utils-4.1,
    // xenstore-utils and libxenstore3.0
//  "(lib)?xen(store)?";

    // For more information about Python regular expressions, see
    // https://docs.python.org/3/howto/regex.html
};

// This option allows you to control if on a unclean dpkg exit
// unattended-upgrades will automatically run
//   dpkg --force-confold --configure -a
// The default is true, to ensure updates keep getting installed
//Unattended-Upgrade::AutoFixInterruptedDpkg "true";

// Split the upgrade into the smallest possible chunks so that
// they can be interrupted with SIGTERM. This makes the upgrade
// a bit slower but it has the benefit that shutdown while a upgrade
// is running is possible (with a small delay)
//Unattended-Upgrade::MinimalSteps "true";

// Install all updates when the machine is shutting down
// instead of doing it in the background while the machine is running.
// This will (obviously) make shutdown slower.
// Unattended-upgrades increases logind's InhibitDelayMaxSec to 30s.
// This allows more time for unattended-upgrades to shut down gracefully
// or even install a few packages in InstallOnShutdown mode, but is still a
// big step back from the 30 minutes allowed for InstallOnShutdown previously.
// Users enabling InstallOnShutdown mode are advised to increase
// InhibitDelayMaxSec even further, possibly to 30 minutes.
//Unattended-Upgrade::InstallOnShutdown "false";

// Send email to this address for problems or packages upgrades
// If empty or unset then no email is sent, make sure that you
// have a working mail setup on your system. A package that provides
// 'mailx' must be installed. E.g. "user@example.com"
//Unattended-Upgrade::Mail "";

// Set this value to one of:
//    "always", "only-on-error" or "on-change"
// If this is not set, then any legacy MailOnlyOnError (boolean) value
// is used to chose between "only-on-error" and "on-change"
//Unattended-Upgrade::MailReport "on-change";

// Remove unused automatically installed kernel-related packages
// (kernel images, kernel headers and kernel version locked tools).
//Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// Do automatic removal of newly unused dependencies after the upgrade
//Unattended-Upgrade::Remove-New-Unused-Dependencies "true";

// Do automatic removal of unused packages after the upgrade
// (equivalent to apt-get autoremove)
//Unattended-Upgrade::Remove-Unused-Dependencies "false";

// Automatically reboot *WITHOUT CONFIRMATION* if
//  the file /var/run/reboot-required is found after the upgrade
Unattended-Upgrade::Automatic-Reboot "false";

// Automatically reboot even if there are users currently logged in
// when Unattended-Upgrade::Automatic-Reboot is set to true
//Unattended-Upgrade::Automatic-Reboot-WithUsers "true";

// If automatic reboot is enabled and needed, reboot at the specific
// time instead of immediately
//  Default: "now"
//Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Use apt bandwidth limit feature, this example limits the download
// speed to 70kb/sec
//Acquire::http::Dl-Limit "70";

// Enable logging to syslog. Default is False
Unattended-Upgrade::SyslogEnable "true";

// Specify syslog facility. Default is daemon
// Unattended-Upgrade::SyslogFacility "daemon";

// Download and install upgrades only on AC power
// (i.e. skip or gracefully stop updates on battery)
// Unattended-Upgrade::OnlyOnACPower "true";

// Download and install upgrades only on non-metered connection
// (i.e. skip or gracefully stop updates on a metered connection)
// Unattended-Upgrade::Skip-Updates-On-Metered-Connections "true";

// Verbose logging
// Unattended-Upgrade::Verbose "false";

// Print debugging information both in unattended-upgrades and
// in unattended-upgrade-shutdown
// Unattended-Upgrade::Debug "false";

// Allow package downgrade if Pin-Priority exceeds 1000
// Unattended-Upgrade::Allow-downgrade "false";

// When APT fails to mark a package to be upgraded or installed try adjusting
// candidates of related packages to help APT's resolver in finding a solution
// where the package can be upgraded or installed.
// This is a workaround until APT's resolver is fixed to always find a
// solution if it exists. (See Debian bug #711128.)
// The fallback is enabled by default, except on Debian's sid release because
// uninstallable packages are frequent there.
// Disabling the fallback speeds up unattended-upgrades when there are
// uninstallable packages at the expense of rarely keeping back packages which
// could be upgraded or installed.
// Unattended-Upgrade::Allow-APT-Mark-Fallback "true";

EOF

systemctl restart unattended-upgrades
unattended-upgrades --dry-run --debug

fi

# restrict root access
if [ "$DO_RESTRICT_ROOT" = "true" ]; then

    if [ -z "$SSH_USERNAME" ]; then
        echo "Error: SSH_USERNAME is required."
        exit 1
    fi

    if [ -n "$SSH_KEY" ]; then

        # Use SSH keys for authentication
        echo "Restricting root access with SSH key..."

        useradd -m -d /home/$SSH_USERNAME -s /bin/bash $SSH_USERNAME

        mkdir -p /home/$SSH_USERNAME/.ssh

        echo "$SSH_KEY" | tee /home/$SSH_USERNAME/.ssh/authorized_keys >/dev/null

        chown -R $SSH_USERNAME:$SSH_USERNAME /home/$SSH_USERNAME/.ssh
        chmod 700 /home/$SSH_USERNAME/.ssh
        chmod 600 /home/$SSH_USERNAME/.ssh/authorized_keys

        # Add user to sudoers
        echo "$SSH_USERNAME ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/10-$SSH_USERNAME-users > /dev/null

        # Ensure public key authentication is enabled in SSH server configuration
        sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

        # Update any conflicting settings in included config files
        for config_file in /etc/ssh/sshd_config.d/*.conf; do
            if grep -q 'PubkeyAuthentication no' "$config_file"; then
                sed -i 's/^#\?PubkeyAuthentication no/PubkeyAuthentication yes/' "$config_file"
            fi
        done

        # Disable root SSH login
        sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config

    elif [ -n "$SSH_PASSWD" ]; then

        # Ensure password authentication is enabled in SSH server configuration
        echo "Enabling password authentication for SSH..."

        # This directive enables or disables challenge-response authentication mechanisms,
        # such as password-based login with additional prompts or One-Time Passwords (OTP).
        # If "yes," SSH may interact with PAM to provide multi-step authentication.
        # If "no," such mechanisms are disabled, and simpler methods like plain password
        # authentication (controlled by PasswordAuthentication) or public key authentication
        # are used instead.
        sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config

        # Update PasswordAuthentication in the main sshd_config file
        # This directive controls whether the SSH server allows password-based authentication.
        # If set to "yes," users can authenticate using their account passwords.
        # If set to "no," password-based logins are disabled, and users must authenticate
        # using alternative methods such as public key authentication.
        sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

        # Update PasswordAuthentication in all included config files
        for config_file in /etc/ssh/sshd_config.d/*.conf; do
            if grep -q 'PasswordAuthentication no' "$config_file"; then
                sed -i 's/^#\?PasswordAuthentication no/PasswordAuthentication yes/' "$config_file"
            fi
        done

        # Use password for authentication
        echo "Restricting root access with password..."

        useradd -m -d /home/$SSH_USERNAME -s /bin/bash $SSH_USERNAME

        echo "$SSH_USERNAME:$SSH_PASSWD" | chpasswd
        echo "$SSH_USERNAME ALL=(ALL) NOPASSWD:ALL" | tee /etc/sudoers.d/10-$SSH_USERNAME-users > /dev/null

        # Disable root SSH login
        sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config

    else

        echo "Error: Either SSH_KEY or SSH_PASSWD must be defined to restrict root access."
        exit 1

    fi

    # Restart SSH service
    systemctl restart sshd

fi
