#!/bin/bash

help()
{
    echo "This script installs and configures Nginx server on Ubuntu"
    echo "Parameters:"
    echo "-u username usedfor the basic authentication"
    echo "-p password used for the basic authentication"
}

# Log method to control/redirect log output
log()
{
    echo "$1"
}

log "Begin execution of Nginx script extension on ${HOSTNAME}"

if [ "${UID}" -ne 0 ];
then
    log "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi

# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM
grep -q "${HOSTNAME}" /etc/hosts
if [ $? == 0 ]
then
  echo "${HOSTNAME}found in /etc/hosts"
else
  echo "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hsots file if not there
  echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etchosts"
fi

#Script Parameters
USERNAME="azureuser"
PASSWORD="WSXzaq123"

#Loop through options passed
while getopts :u:p:h optname; do
    log "Option $optname set with value ${OPTARG}"
  case $optname in
    u) #set cluster name
      USERNAME=${OPTARG}
      ;;
    p) #static discovery endpoints
      PASSWORD=${OPTARG}
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

# Install Nginx
install_nginx()
{
	log "Installing Nginx"
	apt-get update
	apt-get -y install nginx
}

# Primary Install Tasks
#########################

#
#Install Nginx
#-----------------------
install_nginx

#Configure Nginx settings
#---------------------------

echo "upstream elasticsearch {" >> /etc/nginx/sites-available/elasticsearch
echo "	server 127.0.0.1:9200;" >> /etc/nginx/sites-available/elasticsearch
echo "	keepalive 15;" >> /etc/nginx/sites-available/elasticsearch
echo "}" >> /etc/nginx/sites-available/elasticsearch

echo "upstream kibana {" >> /etc/nginx/sites-available/elasticsearch
echo "	server 127.0.0.1:5601;" >> /etc/nginx/sites-available/elasticsearch
echo "	keepalive 15;" >> /etc/nginx/sites-available/elasticsearch
echo "}" >> /etc/nginx/sites-available/elasticsearch

echo "server {" >> /etc/nginx/sites-available/elasticsearch
echo "	listen 9201;" >> /etc/nginx/sites-available/elasticsearch
echo "	auth_basic \"Elasticsearch authentication\";" >> /etc/nginx/sites-available/elasticsearch
echo "	auth_basic_user_file /etc/nginx/elasticsearch-passwords;" >> /etc/nginx/sites-available/elasticsearch

echo "	location / {" >> /etc/nginx/sites-available/elasticsearch
echo "		proxy_pass http://elasticsearch;" >> /etc/nginx/sites-available/elasticsearch
echo "		proxy_http_version 1.1;" >> /etc/nginx/sites-available/elasticsearch
echo "		proxy_set_header Connection \"Keep-Alive\";" >> /etc/nginx/sites-available/elasticsearch
echo "		proxy_set_header Proxy-Connection \"Keep-Alive\";" >> /etc/nginx/sites-available/elasticsearch
echo "	}" >> /etc/nginx/sites-available/elasticsearch
echo "}" >> /etc/nginx/sites-available/elasticsearch

echo "server {" >> /etc/nginx/sites-available/elasticsearch
echo "	listen 5602;" >> /etc/nginx/sites-available/elasticsearch
echo "	auth_basic \"Elasticsearch authentication\";" >> /etc/nginx/sites-available/elasticsearch
echo "	auth_basic_user_file /etc/nginx/elasticsearch-passwords;" >> /etc/nginx/sites-available/elasticsearch

echo "	location / {" >> /etc/nginx/sites-available/elasticsearch
echo "		proxy_pass http://elasticsearch;" >> /etc/nginx/sites-available/elasticsearch
echo "		proxy_http_version 1.1;" >> /etc/nginx/sites-available/elasticsearch
echo "		proxy_set_header Connection \"Keep-Alive\";" >> /etc/nginx/sites-available/elasticsearch
echo "		proxy_set_header Proxy-Connection \"Keep-Alive\";" >> /etc/nginx/sites-available/elasticsearch
echo "	}" >> /etc/nginx/sites-available/elasticsearch
echo "}" >> /etc/nginx/sites-available/elasticsearch


# Create configuration file for the basic authentication
printf "$USERNAME:$(openssl passwd -1 $PASSWORD)\n" > /etc/nginx/elasticsearch-passwords

# Create symbolic link
ln /etc/nginx/sites-available/elasticsearch /etc/nginx/sites-enabled

# Reload Nginx configuration
service nginx reload
