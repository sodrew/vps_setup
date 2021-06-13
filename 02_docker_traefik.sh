#!/bin/bash

# create the place where we'll store our traefik container on the host
sudo mkdir /opt/traefik /opt/shared

# tell docker how we'd like to setup our container
sudo tee /opt/traefik/docker-compose.yml <<EOL
version: "3.3"

services:

    traefik:
        # image: "traefik:latest"
        image: "traefik:v2.2"
        container_name: "traefik"
        restart: always
        ports:
            - "80:80"
            - "443:443"
            - "8080:8080"
        networks:
            - traefik_proxy
        volumes:
            # Allow Traefik can listen to the Docker events
            - /var/run/docker.sock:/var/run/docker.sock
            # Pass the static Traefik config from the host to the Traefik container
            - /opt/traefik/traefik.toml:/etc/traefik/traefik.toml
            # Share the dynamic config across containers
            - /opt/shared:/shared

networks:
  traefik_proxy:
    external: true
EOL

# create the static config: traefik.toml (within the container, it'll be looked for in /etc/traefik)
# however, we create it on the host in our project directory, and use the "volumes" config in docker-compose
# to link it into the container
emailAddress="user@gmail.com"
domainName="example.com"
sudo tee /opt/traefik/traefik.toml  <<EOL
[global]
  sendAnonymousUsage = false

[log]
  level = "DEBUG"

[api]
  dashboard = true

[providers.file]
  filename = "/shared/traefik_dyn.toml"

[entryPoints]
  [entryPoints.web]
    address = ":80"
    [entryPoints.web.http]
      [entryPoints.web.http.redirections]
        [entryPoints.web.http.redirections.entryPoint]
          to = "websecure"
          scheme = "https"
  [entryPoints.websecure]
    address = ":443"
    [entryPoints.websecure.http.tls]
      certResolver = "myresolver"
  [entryPoints.traefik]
    address = ":8080"
    [entryPoints.dashboard.auth.basic]
        users = ["admin:19081987"]

[certificatesResolvers.myresolver.acme]
    email = "$emailAddress"
    storage = "shared/acme.json"
    entryPoint = "websecure"
    [certificatesResolvers.myresolver.acme.dnsChallenge]
EOL


emailAddress="user@gmail.com"
domainName="example.com"
sudo tee /opt/shared/traefik.toml  <<EOL
[http]
  [http.routers]
    # Define a connection between requests and services
    [http.routers.acuparse]
      # what domain we expect the request to come for
      rule = "Host(`$domainName`)"
      # how we exepct the request to come
      entryPoints = ["websecure"]
      # define this since we are using websecure
      certResolver = "myresolver"
      # forward to the defined entry in http.services
      service = "acuparse"
    [http.routers.dashboard]
      entryPoints = ["traefik"]
      rule = "Host(`$domainName`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))"
      # this is the default service name provided by Traefik
      service = "api@internal"

[http.services]
  [http.services.acuparse]
    [[http.services.acuparse.loadBalancer.servers]]
      url = "https://$domainName"

      

EOL

emailAddress="user@gmail.com"
domainName="example.com"
sudo tee docker-compose.yml <<EOL
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
            - "traefik.http.routers.traefik.rule=Host(\`$domainName\`) && PathPrefix(\`/dashboard\`)" # escaping backticks for heredoc
            - "traefik.http.routers.traefik.service=api@internal"
            - "traefik.http.routers.traefik.tls.certresolver=leresolver"
            - "traefik.http.routers.traefik.entrypoints=websecure"
            - "traefik.http.routers.traefik.middlewares=authtraefik"
            - "traefik.http.middlewares.authtraefik.basicauth.users=user:$$apr1$$q8eZFHjF$$Fvmkk//V6Btlaf2i/ju5n/" # user/password

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
# https://doc.traefik.io/traefik/getting-started/configuration-overview/#the-dynamic-configuration
# https://doc.traefik.io/traefik/routing/overview/
# https://stackoverflow.com/questions/64022537/traefik-runs-but-dont-uses-toml-file