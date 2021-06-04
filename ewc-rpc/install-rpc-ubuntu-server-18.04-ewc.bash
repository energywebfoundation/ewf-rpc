#!/bin/bash

# Make the script exit on any error
set -e
set -o errexit
DEBIAN_FRONTEND=noninteractive

# Directory where is script file
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Current directory
CURRENT_BASE_DIR="${PWD}"

# Configuration Block - Docker checksums are the image Id
PARITY_VERSION="openethereum/openethereum:v3.2.5"
DOCKER_COMPOSE_VERSION="1.25.4"

# Chain/Parity configuration
CHAINNAME="EnergyWebChain"
CHAINSPEC_URL="https://raw.githubusercontent.com/energywebfoundation/ewf-chainspec/master/EnergyWebChain.json"

# Collecting information from the user

# Get external IP from OpenDNS
EXTERNAL_IP="$(dig @resolver1.opendns.com ANY myip.opendns.com +short)"

function updateInstance {
  apt-get update -y
}

function networkConfiguration {
  # Add more DNS servers (cloudflare and google) than just the DHCP one to increase DNS resolve stability
  echo "Add more DNS servers"
  echo "dns-nameservers 8.8.8.8 1.1.1.1" >> /etc/network/interfaces
  echo "nameserver 1.1.1.1" >> /etc/resolv.conf
  echo "nameserver 8.8.8.8" >> /etc/resolv.conf

  # Disable the DHPC clients ability to overwrite resolv.conf
  echo 'make_resolv_conf() { :; }' > /etc/dhcp/dhclient-enter-hooks.d/leave_my_resolv_conf_alone
  chmod 755 /etc/dhcp/dhclient-enter-hooks.d/leave_my_resolv_conf_alone

}
# Make sure locales are properly set and generated
function setLocales {

  

  apt-get install locales -y
  echo "Setup locales"
  cat > /etc/locale.gen << EOF
de_DE.UTF-8 UTF-8
en_US.UTF-8 UTF-8
EOF
  locale-gen
  echo -e 'LANG="en_US.UTF-8"\nLANGUAGE="en_US:en"\n' > /etc/default/locale
  source /etc/default/locale

}

function installDependencies {
  echo "Installing dependencies"
  apt-get install -y curl net-tools dnsutils expect jq iptables-persistent debsums chkrootkit
}

function installDocker {
  # Install current stable Docker
  echo "Install Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  chmod +x get-docker.sh
  ./get-docker.sh
  rm get-docker.sh

  # Install docker-compose
  echo "Installing docker compose..."
  curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
  chmod +x /usr/bin/docker-compose

}

function prepareParityDirectories {
  # Create the directory structure
  mkdir docker-stack
  chmod 750 docker-stack
  cd docker-stack
  mkdir config
  mkdir chain-data

  touch config/peers

  # chown 1000:1000 chain-data
  chmod 777 chain-data
}

## Files that get created

function writeDockerCompose {
cat > docker-compose.yml << 'EOF'
version: '3.7'
services:
  parity:
    image: ${PARITY_VERSION}
    restart: always
    command:
      --config /parity/config/parity.toml

    volumes:
      - ./config:/parity/config:ro
      - ./chain-data:/home/openethereum/.local/share/io.parity.ethereum/
  web:
    image: nginx:stable
    restart: always
    depends_on:
      - parity
    ports:
      - "80:80"
      - "443:443"
    env_file:
      - ./.env
    volumes:
      - "./nginx.conf:/etc/nginx/nginx.conf:ro"
      - "${NGINX_CERT}:/etc/nginx/nginx.crt:ro"
      - "${NGINX_KEY}:/etc/nginx/nginx.key:ro"
EOF

cat > .env << EOF
# Parity
PARITY_VERSION=$PARITY_VERSION
# Nginx
NGINX_CERT=./nginx.crt
NGINX_KEY=./nginx.key
EOF

chmod 640 .env
chmod 640 docker-compose.yml
}

function writeSSHConfig {
cat > /etc/ssh/sshd_config << EOF
Port 22
PermitRootLogin no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
TCPKeepAlive no
MaxAuthTries 2

ClientAliveCountMax 2
Compression no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem	sftp	/usr/lib/openssh/sftp-server
EOF
}

function writeDockerConfig {
cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
}

function writeParityConfig {
cat > config/parity.toml << EOF
[parity]
chain = "/parity/config/chainspec.json"
no_persistent_txqueue = true

[rpc]
disable = false
port = 8545
interface = "0.0.0.0"
cors = ["all"]
apis = ["eth", "net", "parity","web3"]
server_threads = 48

[websockets]
disable = false
interface = "0.0.0.0"
port = 8546

[ipc]
disable = true

[secretstore]
disable = true

[network]
port = 30303
min_peers = 25
max_peers = 50
discovery = true
warp = false
allow_ips = "all"
snapshot_peers = 0
max_pending_peers = 64
reserved_peers = "/parity/config/peers"

[footprint]
db_compaction = "ssd"

[snapshots]
enable = true
EOF
chmod 644 config/parity.toml
}

function writeNginxConfig-HTTPS {
cat > ./nginx.conf << 'EOF'
user  nginx;
worker_processes  4;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
  worker_connections  1024;
}


http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
  access_log  /var/log/nginx/access.log  main;

  sendfile        on;

  keepalive_timeout  65;

  server {
    listen 80;
    location / {
      return 301 https://$host$request_uri;
    }

  }
  server {
    listen 443 ssl;
    ssl_certificate     /etc/nginx/nginx.crt;
    ssl_certificate_key    /etc/nginx/nginx.key;

    location / {
            proxy_connect_timeout   150;
            proxy_send_timeout      100;
            proxy_read_timeout      100;
            proxy_buffers           4 32k;
            client_max_body_size    8m;
            client_body_buffer_size 128k;
            proxy_pass http://parity:8545;
    }
    location /ws {
            proxy_connect_timeout   150;
            proxy_send_timeout      100;
            proxy_read_timeout      100;
            proxy_buffers           4 32k;
            client_max_body_size    8m;
            client_body_buffer_size 128k;
            proxy_pass http://parity:8546;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'Upgrade';
    }
  }
}

EOF
}

function writeNginxConfig-HTTP {
cat > ./nginx.conf << 'EOF'
user  nginx;
worker_processes  4;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;


events {
  worker_connections  1024;
}


http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
  access_log  /var/log/nginx/access.log  main;

  sendfile        on;

  keepalive_timeout  65;

  server {
    listen 80;

    location / {
            proxy_connect_timeout   150;
            proxy_send_timeout      100;
            proxy_read_timeout      100;
            proxy_buffers           4 32k;
            client_max_body_size    8m;
            client_body_buffer_size 128k;
            proxy_pass http://parity:8545;
    }
    location /ws {
            proxy_connect_timeout   150;
            proxy_send_timeout      100;
            proxy_read_timeout      100;
            proxy_buffers           4 32k;
            client_max_body_size    8m;
            client_body_buffer_size 128k;
            proxy_pass http://parity:8546;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'Upgrade';
    }
  }
}

EOF
}

function generateDummySSL {
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout ./nginx.key -out ./nginx.crt -subj "/C=US/ST=US/L=US/O=Example/OU=Example/CN=example.com"
}

function showParityLogs {
  cd docker-stack
  docker-compose logs --tail 50 parity
  cd $CURRENT_BASE_DIR
}

function showNginxLogs {
  cd docker-stack
  docker-compose logs --tail 50 web
  cd $CURRENT_BASE_DIR
}
# RPC Node installation
function install {
  SSL_OPTION=${1:-HTTP}
  echo "Installing RPC with nginx configured as $SSL_OPTION"

  updateInstance
  setLocales
  installDependencies
  installDocker

  # Secure SSH by disable password login and only allowing login as user with keys.
  echo "Securing SSH..."
  writeSSHConfig
  service ssh restart
  #DNS & DHCP
  networkConfiguration
  # Install Docker & Docker-Compose
  # Write docker config
  writeDockerConfig
  service docker restart

  # Prepare and pull docker images and verify their checksums
  echo "Prepare Docker..."
  docker pull $PARITY_VERSION

  # Prepare necessary directories and cd into that dir
  prepareParityDirectories

  # Prepare the parity rpc config
  writeParityConfig

  echo "Fetch Chainspec..."
  wget $CHAINSPEC_URL -O config/chainspec.json
  
  # Generate Dummy ssl to start composition
  generateDummySSL

  # Write nginx basic config
  writeNginxConfig-$SSL_OPTION

  # Write the docker-compose  & .env file to disk
  writeDockerCompose

  # start everything up
  docker-compose up -d


  # Print install summary
  cd $CURRENT_BASE_DIR
  echo "==== EWF Affiliate RPC Node Install Summary ====" > install-summary.txt
  echo "Chain name: $CHAINNAME" >> install-summary.txt
  echo "IP Address: $EXTERNAL_IP" >> install-summary.txt
  echo "Installation script location: $SCRIPT_DIR" >> install-summary.txt
  cat install-summary.txt

}

function install-http {
  install HTTP
}

function install-https {
  install HTTPS
}

# Check and run declared function
if declare -f "$1" > /dev/null
then
  "$@"
else
  # Show a helpful error
  echo "'$1' is not a known function name" >&2
  exit 1
fi
