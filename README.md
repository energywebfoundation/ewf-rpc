# EWF RPC node install scripts

EWC and Volta RPC node installation scripts.

## Quickstart

1. Install operating system and prepare dedicated host for RPC node

    At least we recommend to run AWS EC2 instance with minimum resources like `t3.medium`.
    Basic required instance specification:
      - OS: Ubuntu Server 18.04
      - CPU: 2
      - RAM: 4GB
      - Hard drive: minimum 60GB at this moment

    Network security recommendations:
      - Incoming SSH connection only from specific IPS or via VPN.
      - Incoming HTTP/HTTPS connections via ports 80/443 (Can be limitated to specific locations depending on your needs)
      - Open outgoing connection to the internet. Node should be regulary updated and have to be connected to the blockchain network.

1. Connect to the host and download choosen installation script:

    - Volta: `wget -O install-rpc.bash https://raw.githubusercontent.com/energywebfoundation/ewf-rpc/master/volta-rpc/install-rpc-ubuntu-server-18.04-volta.bash`
    
    - EWC: `wget -O install-rpc.bash https://raw.githubusercontent.com/energywebfoundation/ewf-rpc/master/ewc-rpc/install-rpc-ubuntu-server-18.04-ewc.bash`

1. Run installation script in selected option

    - Basic possibility with HTTP Only: `sudo bash install-rpc.bash install-http`

      In this configuration we receive ready to use RPC with connection provided via HTTP on port 80

    - Second option with HTTPS: `sudo bash install-rpc.bash install-https`

      In this configuration we receive RPC with self-signed certificate which is not allowed by most browsers.
      Here afer installation user is obligated to provide his own certificates.

1. Now we have to wait till validator will be fully synced

## HTTPS Certificate Informations

In situation when we chose HTTPS option our script will generate simple self-signed certificate which should be changed.

Certificates are dynamically binded to nginx container based on path inside `docker-stack/.env` file. We have two variables `NGINX_CERT` and `NGINX_KEY` where we can provide path to new dedicated certificates.

Members can use any trusted ssl certificates. For our composition does not matter if any certbot will provide files or another service - they just must be readable for nginx.

After certificate change nginx container restart is required, so please run below command from `docker-stack` directory:

`docker-compose restart web`

Additionally verify if nginx started correctly and we do not have any errors related to that certificates in logs

`docker-compose logs --tail 50 web`

## Maintainers

**Primary:** Kamil Rosenberger (@Berger91)