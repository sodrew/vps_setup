#!/bin/bash

#set the time to match our timezone for logging purposes
sudo timedatectl set-timezone America/New_York

# replace() {
#     ex -sc '/^\s*[^#]/s/^/#/' -cx bla.conf
#   sed -i '' "s/^$1/#$1/" $CONFIG
# }

#-----------------------------------------------------------------------------------
# [1] PATCHING "An incredible amount of attack surface can be eliminated by merely staying vigilant about patching"

# Update repos
apt-get update
# Upgrade existing packages to latest
apt-get upgrade
# Set auto-update
apt install unattended-upgrades
dpkg-reconfigure unattended-upgrades

    # modify this conf file
        # vim /etc/apt/apt.conf.d/50unattended-upgrades
        # Uncomment these lines :
            # "${distro_id}:${distro_codename}-updates";
            # Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
            # Unattended-Upgrade::Remove-Unused-Dependencies "true";
            # Unattended-Upgrade::Automatic-Reboot "true";
            # Unattended-Upgrade::Automatic-Reboot-Time "02:00"
        # Uncomment and edit this line
            # Unattended-Upgrade::Mail "root";
        # Add this line if you only want to get mails on errors
            # Unattended-Upgrade::MailOnlyOnError "true";
    # modify this conf file
        # vim /etc/apt/apt.conf.d/20auto-upgrades
        # modify these lines to make it weekly:
            # APT::Periodic::Update-Package-Lists "7";
            # APT::Periodic::Unattended-Upgrade "7";
        # add these lines
            # APT::Periodic::Download-Upgradeable-Packages "7";
            # APT::Periodic::AutocleanInterval "7";
# to test this out
unattended-upgrade -v -d --dry-run

#-----------------------------------------------------------------------------------
# [2] WEBSERVER "Apache need not broadcast so much info"

# enable key modules to adjust headers, enable ssl, and turn off directory listing
a2enmod headers
a2dismod --force autoindex
# a2enmod ssl
# a2enmod proxy proxy_html

cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.bak
# Add the following lines and restart the apache service.
cat >> /etc/apache2/apache2.conf <<EOL
ServerSignature Off 
ServerTokens Prod
TraceEnable Off
Header unset Server
Header unset X-Powered-By
EOL

# restart the services
systemctl restart apache2

#-----------------------------------------------------------------------------------
# [2] MAIL "setup send only mail"

# setup your domain's A record to point to the ipv4 address of this VPS
# setup your domain's AAAA record to point to the ipv6 address of this VPS
# setup reverse DNS on your VPS to point back to your domain

# install Postfix by running the following command:
apt install postfix
    # in the config screen, select "internet site", but if config screen doesn't come up
    # dpkg-reconfigure postfix
# configure postfix to send only
cp /etc/postfix/main.cf /etc/postfix/main.cf.bak
vi /etc/postfix/main.cf
    # find this line: 
        # inet_interfaces = all
    # change it to
        # inet_interfaces = loopback-only
    # find this line:
        # smtpd_banner = $myhostname ESMTP $mail_name (Ubuntu)
    # change it to
        # smtpd_banner = $myhostname ESMTP
    # find this line:
        # mydestination = $myhostname, <domain_name>, localhost.com, , localhost
    # change it to
        # mydestination = localhost.$mydomain, localhost, $myhostname
    # add this line if you want to strip off subdomains from the email address:
        # masquerade_domains = $myhostname
# restart to reflect the config changes
systemctl restart postfix

# to test the mail service, you need to install mailutils
apt install mailutils

emailAddress="asdf@asdf.com"

# send a test note to the email of your choice
echo "This is the body of the email" | mail -s "Test Email" $emailAddress

# setup email to forward to the email of your choice
cp /etc/aliases /etc/aliases.bak
cat >> /etc/aliases <<EOL
root:  $emailAddress
EOL

# test that this works
echo "This is the body of the email" | mail -s "Forwarding" root

# setup SMTP encryption
# install the scripts to register
apt install certbot
domainName=asdf.com
# request a free TLS certificate from Let’s Encrypt; but we'll need to stop apache so that it succeeds
systemctl stop apache2
certbot certonly --standalone --rsa-key-size 4096 --agree-tos --preferred-challenges http -d $domainName
systemctl start apache2
# you can ignore the renewal as that is setup in systemd, just run this command to validate
systemctl list-timers

# update postfix conf to use this key
vi /etc/postfix/main.cf
    # find this line:
        # smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
        # smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
    # change it to
        # smtpd_tls_cert_file=/etc/letsencrypt/live/your_domain/fullchain.pem
        # smtpd_tls_key_file=/etc/letsencrypt/live/your_domain/privkey.pem

echo "This is the body of the email" | mail -s "Test Encrpyted email" $emailAddress

#-----------------------------------------------------------------------------------
# [3] ACCOUNTS "lock down users"

# check for super user accounts
    # awk -F: '($3=="0"){print}' /etc/passwd
# check for accounts with Empty Passwords
    # cat /etc/shadow | awk -F: '($2==""){print $1}'
# if you find any, lock Accounts (prepends a ! to the user’s password hash):
    # passwd -l <accountName>

# let's define the new user name as a variable going forward
accountName="admin"
# add non-root account (create a user with the default configuration defined in ‘/etc/skel’)
adduser $accountName
# create new user with sudo rights
usermod -aG sudo $accountName
# lock down the root account if needed
    # become the new user
    # su $accountName
    # disable root login
    # sudo passwd -l root

#-----------------------------------------------------------------------------------
# [4] SSH "harden SSH"

# set the port variable
sshPort=22

# list out current settings
# sshd -T

# backup the config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# override the config
cat > /etc/ssh/sshd_config <<EOL
LogLevel VERBOSE
Port $sshPort
Protocol 2
AllowUsers asc
PermitRootLogin no
PermitEmptyPasswords no
MaxAuthTries 2
MaxSessions 2
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive NO
Compression NO
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitUserEnvironment no
ChallengeResponseAuthentication no
UsePAM yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem       sftp    /usr/lib/openssh/sftp-server
EOL

# restart the service to reflect the config changes
systemctl restart sshd

# if you get an error restarting
    # ssh -t
    # if the error is related to "Missing privilege separation directory: /run/sshd"
        # crontab -e
        # add the following entry:
            # @reboot mkdir -p -m0755 /var/run/sshd && systemctl restart ssh.service

#-----------------------------------------------------------------------------------
# [5] FIREWALL "setup iptables"

# check current settings
iptables -L

# backup current ruleset
mkdir iptables
iptables-save > /etc/iptables/rules.bak

    # Overwrite the current rules
        # iptables-restore < /etc/iptables/rules.bak
    # Add the new rules keeping the current ones
        # iptables-restore -n < /etc/iptables/rules.bak

# flush the tables and start from scratch
# set the default rule to accept
iptables -P INPUT ACCEPT
# Clear input chain
iptables -F INPUT
# Flush the whole iptables
iptables -F

# enable ssh
iptables -A INPUT -p tcp -m tcp --dport $sshPort -m state --state NEW,ESTABLISHED -j ACCEPT
# enable http
iptables -A INPUT -p tcp -m tcp --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
# enable https
iptables -A INPUT -p tcp -m tcp --dport 443 -m state --state NEW,ESTABLISHED -j ACCEPT
# enable loop back
iptables -A INPUT -I lo -j ACCEPT
# drops all packets that don't match the rules above
iptables -P INPUT DROP

# make sure iptables persists
apt-get install iptables-persistent

#-----------------------------------------------------------------------------------
# [6] SECTOOLS "install security and monitoring tools"

# install lynis
# verify that lynis is out of date with what is currently available
apt-cache policy lynis
    # if it is out of date with the version at https://packages.cisofy.com/
    # download and install the Lynis repository PGP signing key from a central keyserver;
    wget -O - https://packages.cisofy.com/keys/cisofy-software-public.key | sudo apt-key add -
    # enable using HTTPS for secure transport
    apt install apt-transport-https
    # only download english
    echo 'Acquire::Languages "none";' | sudo tee /etc/apt/apt.conf.d/99disable-translations
    # install the lynis repo
    echo "deb https://packages.cisofy.com/community/lynis/deb/ stable main" | sudo tee /etc/apt/sources.list.d/cisofy-lynis.list
    # resynchronize the package repositories to their latest versions;
apt update
apt install lynis

# run lynis (if you have less trust in the package, run as non-root)
lynis audit system

# examine the warnings
user=$(whoami)
grep -i "^exceptions" /home/$user/lynis-report.dat
grep -i "^warning" /home/$user/lynis-report.dat
grep -i "^suggestion" /home/$user/lynis-report.dat
# to customize what you see
# default profile is located here /etc/lynis/default.prf, if no other is specified it gets used
# let's make a copy and edit it
cp /etc/lynis/default.prf /etc/lynis/custom.prf
cat >> /etc/lynis/custom.prf <<EOL
skip-test=KRNL-5788
skip-test=KRNL-5820
skip-test=KRNL-6000
skip-test=FILE-6310 
skip-test=USB-1000
skip-test=HRDN-7222
skip-test=NETW-2704
skip-test=NETW-2705
skip-test=PKGS-7410
EOL

# run lynis (if you have less trust in the package, run as non-root)
lynis audit system --profile /etc/lynis/custom.prf

# it's also possible to audit dockerfiles
# lynis audit dockerfile Dockerfile

# install fail2ban
sudo apt-get install fail2ban
cp -rv /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
systemctl start fail2ban

# Installing chkrootkit on Ubuntu 20.04
apt install chkrootkit
# Open /etc/chkrootkit.conf , Replace the first line to reflect RUN_DAILY="true"



#-----------------------------------------------------------------------------------
# REFERENCES

# Display current connections
    # netstat -tulpn

# Display Services and Their Status
    # service --status-all

# Common Configuration File Locations
    # /etc/apache/apache2.conf #Apache 2
    # /etc/ssh/sshd_config #SSH Server
    # /etc/mysql/mysql.cnf #MySQL
    # /var/lib/mysql/ #This entire directory contains all of the database in MySQL

# Common default log locations:
    # /var/log/message — Where whole system logs or current activity logs are available.
    # /var/log/auth.log — Authentication logs.
    # /var/log/kern.log — Kernel logs.
    # /var/log/cron.log — Crond logs (cron job).
    # /var/log/maillog — Mail server logs.
    # /var/log/boot.log — System boot log.
    # /var/log/mysqld.log — MySQL database server log file.
    # /var/log/secure — Authentication log.
    # /var/log/utmp or /var/log/wtmp — Login records file.
    # /var/log/apt — Apt package manager logs


# sources:
# https://techytrois.com/harden-your-ubuntu-20-04-hosting-server/
# https://octopus.com/docs/runbooks/runbook-examples/routine/hardening-ubuntu
# https://www.nuharborsecurity.com/ubuntu-server-hardening-guide-2/
# https://askubuntu.com/questions/326156/how-to-customize-unattended-upgrades-notification-emails
# https://www.lastbreach.com/blog/quick-guide-hardening-apache2
# https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-postfix-as-a-send-only-smtp-server-on-ubuntu-20-04
# https://upcloud.com/community/tutorials/configure-iptables-ubuntu/
# https://www.howtoforge.com/tutorial/how-to-scan-linux-for-malware-and-rootkits/
# https://kifarunix.com/install-and-setup-lynis-security-auditing-tool-on-ubuntu-20-04/