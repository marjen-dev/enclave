terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0.2" # Adjust the version constraint as needed
    }
    enclave = {
      enrolement_key = var.enclave_enrolment_key
    }
  }
}


resource "docker_container" "enclave" {
  name         = "enclave"
  image        = "enclavenetworks/enclave"
  network_mode = "host"
  capabilities {
    add = ["NET_ADMIN"]
  }
  devices {
    host_path = "/dev/net/tun"
  }
  volumes {
    volume_name    = docker_volume.enclave_config.name
    container_path = "/etc/enclave/profiles"
  }
  volumes {
    volume_name    = docker_volume.enclave_logs.name
    container_path = "/var/log/enclave"
  }
  restart = "unless-stopped"
}


resource "docker_container" "watchtower" {
  image = "containrrr/watchtower"
  name  = "watchtower"
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }
  restart = "unless-stopped"
}


resource "docker_volume" "enclave_config" {
  name = "enclave-config"
}


resource "docker_volume" "enclave_logs" {
  name = "enclave-logs"
}











