#!/bin/bash

set -euo pipefail

sanitize_path()
{
    local input="$1"

    # Convert to lowercase
    local SAFE_NAME=$(echo "$input" | tr '[:upper:]' '[:lower:]')

    # Replace spaces with underscores
    SAFE_NAME=$(echo "$SAFE_NAME" | tr ' ' '_')

    # Replace non-alphanumeric characters except underscores with an underscore
    SAFE_NAME=$(echo "$SAFE_NAME" | sed 's/[^[:alnum:]_]/_/g')

    # Remove multiple consecutive underscores
    SAFE_NAME=$(echo "$SAFE_NAME" | sed 's/_\+/_/g')

    # Remove leading and trailing underscores
    SAFE_NAME=$(echo "$SAFE_NAME" | sed 's/^_//' | sed 's/_$//')

    # If the result is empty, return a default name
    if [ -z "$SAFE_NAME" ]; then
        SAFE_NAME="customer1"
    fi

    echo "$SAFE_NAME"
}

usage="$(basename "$0") [-h] [-g] -c CUSTOMER_NAME -k ENCLAVE_ENROLMENT_KEY -p ENCLAVE_LOCAL_PORT
Provision a customer gateway instance from the template in this folder.
where:
    -h  show this help text
    -g  generate a new certificate authority for the provisioned gateway
    -c  customer name
    -k  enclave enrolment key
    -p  enclave bind port"

GENERATE_CA=false
CUSTOMER_NAME=
ENCLAVE_ENROLMENT_KEY=
ENCLAVE_LOCAL_PORT=

options=':hgc:p:k:'
while getopts $options option; do
  case "$option" in
    h) echo "$usage"; exit;;
    g) GENERATE_CA=true;;
    c) CUSTOMER_NAME=$OPTARG;;
    k) ENCLAVE_ENROLMENT_KEY=$OPTARG;;
    p) ENCLAVE_LOCAL_PORT=$OPTARG;;
    :) printf "missing argument for -%s\n" "$OPTARG" >&2; echo "$usage" >&2; exit 1;;
   \?) printf "illegal option: -%s\n" "$option" >&2; echo "$usage" >&2; exit 1;;
  esac
done

# sanitise customer name to be suitable for use as a directory name
SAFE_NAME=$(sanitize_path "$CUSTOMER_NAME")

# set up directory names
STACK_PATH="./stacks/$SAFE_NAME"
PKI_PATH="$STACK_PATH/pki"
PRIMARY_PATH="$STACK_PATH/primary-gateway"
SECONDARY_PATH="$STACK_PATH/secondary-gateway"

# provision the stack
if [ ! -d "$STACK_PATH" ]; then

    echo "CUSTOMER_NAME:                    $CUSTOMER_NAME"
    echo "STACK_PATH:                       $STACK_PATH"
    echo "PKI_PATH:                         $PKI_PATH"
    echo "PRIMARY_PATH:                     $PRIMARY_PATH"
    echo "SECONDARY_PATH:                   $SECONDARY_PATH"
    echo "ENCLAVE_ENROLMENT_KEY:            $ENCLAVE_ENROLMENT_KEY"

    # mandatory arguments
    if [ ! "$CUSTOMER_NAME" ] || [ ! "$ENCLAVE_ENROLMENT_KEY" ]; then
        echo "arguments -c and -k must be provided"
        echo "$usage" >&2; exit 1
    fi

    mkdir -p $STACK_PATH
    #chown $UID:root $STACK_PATH
    #chmod 770 $STACK_PATH

    mkdir -p $PKI_PATH
    mkdir -p $PRIMARY_PATH
    mkdir -p $SECONDARY_PATH

    # generate pki
    if [ "$GENERATE_CA" == "true" ]; then

        echo "CA_COMMON_NAME:                   Enclave Internet Gateway Authority ($CUSTOMER_NAME)"

        openssl genrsa -out "$PKI_PATH/gateway.key" 4096

        openssl req -x509 \
                    -sha256 \
                    -new \
                    -nodes \
                    -key "$PKI_PATH/gateway.key" \
                    -days 3650 \
                    -out "$PKI_PATH/gateway.crt" \
                    -subj "/C=EN/ST=Wales/L=Newport/O=Enclave Networks/OU=$CUSTOMER_NAME/CN=Enclave Internet Gateway Authority ($CUSTOMER_NAME)"

        # Create a PKCS #7 file from the certificate
        openssl crl2pkcs7 -nocrl -certfile "$PKI_PATH/gateway.crt" -out "$PKI_PATH/gateway.p7b"

        # key can only be used by root.
        chown root:root "$PKI_PATH/gateway.key"
        chmod 600 "$PKI_PATH/gateway.key"
    fi

    # copy templates into stack directories
    cp ./template/docker-compose.primary.yml $PRIMARY_PATH/docker-compose.yml
    cp ./template/docker-compose.secondary.yml $SECONDARY_PATH/docker-compose.yml

    # copy scripts into stack directories
    cp ./template/scripts/initialise-bridge-network.sh $PRIMARY_PATH/initialise-bridge-network.sh
    cp ./template/scripts/initialise-bridge-network.sh $SECONDARY_PATH/initialise-bridge-network.sh

    chmod +x $PRIMARY_PATH/initialise-bridge-network.sh
    chmod +x $SECONDARY_PATH/initialise-bridge-network.sh

    mkdir -p $PRIMARY_PATH/etc/pihole
    mkdir -p $SECONDARY_PATH/etc/pihole

    cp -r $PKI_PATH $PRIMARY_PATH/certs
    cp -r $PKI_PATH $SECONDARY_PATH/certs

    rm -rf $PKI_PATH

    cp -r ./template/blockpage "$PRIMARY_PATH"
    cp -r ./template/blockpage "$SECONDARY_PATH"

    cp -r ./template/caddy "$PRIMARY_PATH"
    cp -r ./template/caddy "$SECONDARY_PATH"

    # initalise variables for containers
    PRIMARY_IP="100.64.0.2"
    PRIMARY_HOSTNAME="gateway-primary"

    SECONDARY_IP="100.64.0.3"
    SECONDARY_HOSTNAME="gateway-secondary"

    if [ -z "$ENCLAVE_LOCAL_PORT" ]; then

        # Function to capture highest docker port, and not pipefile when there are no containers
        get_docker_highest_port() {
            docker ps --format '{{json .}}' \
                | jq -r '.Ports' \
                | grep -o '[0-9]*->' \
                | grep -o '[0-9]*' \
                | sort -n \
                | tail -n 1
        }

        # Run the pipeline and capture the output
        DOCKER_HIGHEST_PORT=$(get_docker_highest_port || true)

        if [ -n "$DOCKER_HIGHEST_PORT" ]; then

            echo "An existing container is bound on port $DOCKER_HIGHEST_PORT, so we must use another."

            NEW_PORT=$(($DOCKER_HIGHEST_PORT + 10))

            ENCLAVE_LOCAL_PORT_ON_PRIMARY=$NEW_PORT
            ENCLAVE_LOCAL_PORT_ON_SECONDARY=$(($NEW_PORT + 1))

        else

            ENCLAVE_LOCAL_PORT_ON_PRIMARY=40000
            ENCLAVE_LOCAL_PORT_ON_SECONDARY=40001

        fi

    else

        ENCLAVE_LOCAL_PORT_ON_PRIMARY = $ENCLAVE_LOCAL_PORT
        ENCLAVE_LOCAL_PORT_ON_SECONDARY = $(($ENCLAVE_LOCAL_PORT + 1))

    fi

    echo "ENCLAVE_LOCAL_PORT_ON_PRIMARY:    $ENCLAVE_LOCAL_PORT_ON_PRIMARY"
    echo "ENCLAVE_LOCAL_PORT_ON_SECONDARY:  $ENCLAVE_LOCAL_PORT_ON_SECONDARY"

    # define a docker bridge name for this instance
    DOCKER_BRIDGE_NAME="$(head /dev/urandom | tr -dc a-z0-9 | head -c 10)_n"

    echo "DOCKER_BRIDGE_NAME:               $DOCKER_BRIDGE_NAME"

    cat <<-EOF | tee "$PRIMARY_PATH/.env" >/dev/null
ENCLAVE_ENROLMENT_KEY=$ENCLAVE_ENROLMENT_KEY
ENCLAVE_VIRTUAL_IP=$PRIMARY_IP
ENCLAVE_LOCAL_PORT=$ENCLAVE_LOCAL_PORT_ON_PRIMARY
PIHOLE_PRIMARY_IP=$PRIMARY_IP
PIHOLE_SECONDARY_IP=$SECONDARY_IP
PIHOLE_HOSTNAME=$PRIMARY_HOSTNAME
DOCKER_BRIDGE_NAME=$DOCKER_BRIDGE_NAME
COMPOSE_PROJECT_NAME=$SAFE_NAME
EOF

    cat <<-EOF | tee "$SECONDARY_PATH/.env" >/dev/null
ENCLAVE_ENROLMENT_KEY=$ENCLAVE_ENROLMENT_KEY
ENCLAVE_VIRTUAL_IP=$SECONDARY_IP
ENCLAVE_LOCAL_PORT=$ENCLAVE_LOCAL_PORT_ON_SECONDARY
PIHOLE_PRIMARY_IP=$PRIMARY_IP
PIHOLE_SECONDARY_IP=$SECONDARY_IP
PIHOLE_HOSTNAME=$SECONDARY_HOSTNAME
DOCKER_BRIDGE_NAME=$DOCKER_BRIDGE_NAME
COMPOSE_PROJECT_NAME=$SAFE_NAME
EOF

else

    echo "$STACK_PATH already exists, taking no action."

fi