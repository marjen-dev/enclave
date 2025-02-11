#!/bin/bash

# Function to find the default route's interface name
default_interface() {
  route get default 2>/dev/null | awk '/interface: / {print $2}'
}

# Function to fetch the user-friendly interface name for networksetup
user_friendly_interface() {
  local system_interface="$1"
  networksetup -listallhardwareports | awk -v iface="$system_interface" '
    BEGIN { hardware_port = "" }
    /^Hardware Port:/ { hardware_port = substr($0, index($0, $3)) }
    /^Device:/ && $2 == iface { print hardware_port; exit }
  '
}

# Function to fetch current DHCP nameservers for a given interface
dhcp_nameservers() {
  local interface="$1"
  ipconfig getpacket "$interface" 2>/dev/null | awk '/domain_name_server/ {gsub(/[{}]/, "", $3); for (i=3; i<=NF; i++) print $i}'
}

# Function to renew the DHCP lease for a given interface
dhcp_renew() {
  local interface="$1"
  sudo networksetup -renewdhcp "$interface"
}

# Function to configure DNS using networksetup
configure_dns() {
  local interface="$1"
  shift
  local dns_servers=("$@")

  echo "Configuring DNS for interface $interface with the following order of nameservers:"
  for server in "${dns_servers[@]}"; do
    echo "  - $server"
  done

  sudo networksetup -setdnsservers "$interface" "${dns_servers[@]}"
}

main() {

  # Exit if not macOS
  if [[ "$(uname)" != "Darwin" ]]; then
    echo "This script is used to refresh the DHCP allocated nameservers on macOS."
    exit 0
  fi

  echo "Determining default network interface..."
  local system_interface=$(default_interface)

  if [ -z "$system_interface" ]; then
    echo "No default network interface found, cannot refresh DNS configuration."
    exit 1
  fi

  echo "Default system interface: $system_interface"

  local user_friendly=$(user_friendly_interface "$system_interface")

  if [ -z "$user_friendly" ]; then
    echo "Could not determine user-friendly interface name, cannot refresh DNS configuration."
    exit 1
  fi

  echo "User-friendly interface: $user_friendly"

  echo "Fetching current DHCP nameservers for $system_interface..."
  local dhcp_servers=($(dhcp_nameservers "$system_interface"))

  if [ -z "$dhcp_servers" ]; then
    echo "No DHCP nameservers found. Attempting to renew DHCP lease."
    dhcp_renew "$user_friendly"
    dhcp_servers=($(dhcp_nameservers "$system_interface"))
    if [ -z "$dhcp_servers" ]; then
      echo "No DHCP nameservers available after renew, cannot refresh DNS configuration."
      exit 1
    fi
  fi

  echo "DHCP nameservers: ${dhcp_servers[@]}"

  echo "Attempting to retrieve Enclave nameserver IP..."
  local enclave_ip=$(enclave get-ip 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$enclave_ip" ]; then
    echo "No Enclave nameserver found, configuring DHCP assigned nameservers only."
    configure_dns "$user_friendly" "${dhcp_servers[@]}"
  else
    echo "Enclave nameserver: $enclave_ip"
    configure_dns "$user_friendly" "$enclave_ip" "${dhcp_servers[@]}"
  fi

  echo "DNS configuration updated successfully."
}

# Run the main function
main
