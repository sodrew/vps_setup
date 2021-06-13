#!/bin/bash

# Add the GPG key for the Docker repository:
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
# Add docker repository to the apt sources:
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
# Lets now update the package database with the new added Docker Package:
sudo apt update
# Install Docker's community edition from the new repository we added:
sudo apt install docker-ce
# Confirm that Docker is running
sudo systemctl status docker

# create a user with docker permissions
userName="admin"
adduser $userName
sudo usermod -aG docker $userName
#  install the tool to create multiple docker containers through the use of YAML
apt-get install docker-compose
# Confirm that Docker compose is installed
docker-compose --version

# generate a separate user for the traefik front end
# change secure_password with the one of your choice
sudo htpasswd -bc /opt/traefik/htaccess user password

# create the place where we'll store our traefik container on the host
sudo mkdir /opt/traefik

emailAddress="user@gmail.com"
domainName="example.com"
sudo tee /opt/traefik/docker-compose.yml <<EOL
version: '3.3'

services:
    traefik:
        # The official v2 Traefik docker image
        image: traefik:v2.2
        # Enables the web UI and tells Traefik to listen to docker
        command:
            - --entrypoints.web.address=:80
            - --entrypoints.websecure.address=:443 
            - --entrypoints.web.http.redirections.entryPoint.to=:443
            - --entrypoints.web.http.redirections.entryPoint.scheme=https
            - --providers.docker=true
            - --api # enables the web ui for traefik
            - --certificatesresolvers.leresolver.acme.email=$emailAddress
            - --certificatesresolvers.leresolver.acme.storage=/acme.json
            - --certificatesresolvers.leresolver.acme.dnschallenge=true
            - --providers.file.directory=/config/
            - --providers.file.watch=true
        ports:
            # docker binds to these ports and sends them to this container
            - "80:80"
            - "443:443" 
        labels:
            # Dashboard
            - "traefik.http.routers.traefik.rule=Host(\`$domainName\`)" # escaping backticks for heredoc
            - "traefik.http.routers.traefik.service=api@internal"
            - "traefik.http.routers.traefik.tls.certresolver=leresolver"
            - "traefik.http.routers.traefik.entrypoints=websecure"
            - "traefik.http.routers.traefik.middlewares=authtraefik"
            - "traefik.http.middlewares.authtraefik.basicauth.usersfile=/htaccess"

            # global redirect to https
            - "traefik.http.routers.http-catchall.rule=hostregexp(\`{host:.+}\`)" # escaping backticks for heredoc
            - "traefik.http.routers.http-catchall.entrypoints=web"
            - "traefik.http.routers.http-catchall.middlewares=redirect-to-https"

            # middleware redirect
            - "traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https"
        volumes:
            - "/var/run/docker.sock:/var/run/docker.sock"
            - "./acme.json:/acme.json"
            - "./config/:/config/"
            - "./htaccess:/htaccess"
            - "/etc/letsencrypt/live/$domainName/fullchain.pem:/fullchain.pem"
            - "/etc/letsencrypt/live/$domainName/privkey.pem:/privkey.pem"
EOL

sudo mkdir config
sudo tee config/certificates.toml <<EOL
[[tls.certificates]]
    certFile = "/fullchain.pem"
    keyFile = "/privkey.pem"
    stores = ["default"]

[tls.defaultCertificate] 
    certFile = "/fullchain.pem"
    keyFile = "/privkey.pem"
EOL

sudo touch acme.json
sudo chmod 600 acme.json

# have docker fetch the image and start the container
docker-compose up -d traefik

# debugging help
    # to list running containers
        # docker ps
    # to look at logs for a container
        # docker logs <container id>
    # to stop a container
        # docker container stop <container id>
    # to start a console in the container
        # docker exec -it <container id> /bin/bash




# https://alexgallacher.com/how-to-choose-and-setup-vps-with-docker-and-docker-compose/
# https://www.qloaked.com/traefik-lets-encrypt-ssl-tutorial/
# https://ligerlearn.com/how-to-edit-files-within-docker-containers/
# https://traefik.io/blog/traefik-2-0-docker-101-fc2893944b9d/
# https://doc.traefik.io/traefik/getting-started/configuration-overview/#the-dynamic-configuration
# https://doc.traefik.io/traefik/routing/overview/
# https://stackoverflow.com/questions/64022537/traefik-runs-but-dont-uses-toml-file