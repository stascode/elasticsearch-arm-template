#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Azure
#
# Permission is hereby granted, free of` charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Trent Swanson (Full Scale 180 Inc)
#
help()
{
    echo "This script installs Elasticsearch cluster on Ubuntu"
    echo "Parameters:"
    echo "-n elasticsearch cluster name"
    echo "-d static discovery endpoints"
    echo "-v elasticsearch version 1.7.2"
    echo "-l install marvel yes/no"
    echo "-k install kibana yes/no"
    echo "-h view this help content"
	echo "-u username used for the basic authentication"
    echo "-p password used for the basic authentication"
}

# Log method to control/redirect log output
log()
{
    # If you want to enable this logging add a un-comment the line below and add your account id
    #curl -X POST -H "content-type:text/plain" --data-binary "${HOSTNAME} - $1" https://logs-01.loggly.com/inputs/<key>/tag/es-extension,${HOSTNAME}
    echo "$1"
}



log "Begin execution of Elasticsearch script extension on ${HOSTNAME}"

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
CLUSTER_NAME="elasticsearch"
ES_VERSION="2.3.2"
DISCOVERY_ENDPOINTS="127.0.0.1"
INSTALL_MARVEL="yes"
INSTALL_KIBANA="yes"
USERNAME="azureuser"
PASSWORD="WSXzaq123"

#Loop through options passed
while getopts :n:d:v:l:k:u:p:sh optname; do
    log "Option $optname set with value ${OPTARG}"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME=${OPTARG}
      ;;
    d) #static discovery endpoints
      DISCOVERY_ENDPOINTS=${OPTARG}
      ;;
    v) #elasticsearch version number
      ES_VERSION=${OPTARG}
      ;;
    l) #install marvel
      INSTALL_MARVEL=${OPTARG}
      ;;
    k) #install kibana
      INSTALL_KIBANA=${OPTARG}
      ;;
    s) #use OS striped disk volumes
      OS_STRIPED_DISK=1
      ;;
	u) #username
	  USERNAME=${OPTARG}
	  ;;
	p) #password
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

# Base path for data disk mount points
# The script assume format /datadisks/disk1 /datadisks/disk2
DATA_BASE="/datadisks"

# Configure Elasticsearch Data Disk Folder and Permissions
setup_data_disk()
{
    log "Configuring disk $1/elasticsearch/data"

    mkdir -p "$1/elasticsearch/data"
    chown -R elasticsearch:elasticsearch "$1/elasticsearch"
    chmod 755 "$1/elasticsearch"
}

# Install Oracle Java
install_java()
{
    log "Installing Java"
    add-apt-repository -y ppa:webupd8team/java
    apt-get -y update  > /dev/null
    echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
    apt-get -y install oracle-java8-installer  > /dev/null
}

# Install Elasticsearch
install_es()
{
    # apt-get install approach
    # This has the added benefit that is simplifies upgrades (user)
    # Using the debian package because it's easier to explicitly control version and less changes of nodes with different versions
    #wget -qO - https://packages.elasticsearch.org/GPG-KEY-elasticsearch | sudo apt-key add -
    #add-apt-repository "deb http://packages.elasticsearch.org/elasticsearch/1.5/debian stable main"
    #apt-get update && apt-get install elasticsearch

    # if [ -z "$ES_VERSION" ]; then
    #     ES_VERSION="1.5.0"
    # fi

    log "Installing Elaticsearch Version - $ES_VERSION"
    sudo wget -q "https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-$ES_VERSION.deb" -O elasticsearch.deb

    sudo dpkg -i elasticsearch.deb
}

# Primary Install Tasks
#########################
#NOTE: These first three could be changed to run in parallel
#      Future enhancement - (export the functions and use background/wait to run in parallel)

#Format data disks (Find data disks then partition, format, and mount them as seperate drives)
#------------------------
bash vm-disk-utils-0.1.sh

#Install Oracle Java
#------------------------
install_java

#
#Install Elasticsearch
#-----------------------
install_es

# Prepare configuration information
# Configure permissions on data disks for elasticsearch user:group
#--------------------------
DATAPATH_CONFIG=""
if [ -d "${DATA_BASE}" ]; then
    for D in `find /datadisks/ -mindepth 1 -maxdepth 1 -type d`
    do
        #Configure disk permissions and folder for storage
        setup_data_disk ${D}
        # Add to list for elasticsearch configuration
        DATAPATH_CONFIG+="$D/elasticsearch/data,"
    done
    #Remove the extra trailing comma
    DATAPATH_CONFIG="${DATAPATH_CONFIG%?}"
else
    #If we do not find folders/disks in our data disk mount directory then use the defaults
    log "Configured data directory does not exist for ${HOSTNAME} using defaults"
fi

HOSTS_CONFIG="[\"${DISCOVERY_ENDPOINTS// /\",\"}\"]"

#Format the static discovery host endpoints for Elasticsearch configuration ["",""] format
#HOSTS_CONFIG="[\"${DISCOVERY_ENDPOINTS//-/\",\"}\"]"

#Configure Elasticsearch settings
#---------------------------
#Backup the current Elasticsearch configuration file
mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.bak

# Set cluster and machine names - just use hostname for our node.name
echo "cluster.name: $CLUSTER_NAME" >> /etc/elasticsearch/elasticsearch.yml
echo "node.name: ${HOSTNAME}" >> /etc/elasticsearch/elasticsearch.yml

# Configure paths - if we have data disks attached then use them
if [ -n "$DATAPATH_CONFIG" ]; then
    log "Update configuration with data path list of $DATAPATH_CONFIG"
    echo "path.data: $DATAPATH_CONFIG" >> /etc/elasticsearch/elasticsearch.yml
fi

# Configure discovery
log "Update configuration with hosts configuration of $HOSTS_CONFIG"
echo "discovery.zen.ping.multicast.enabled: false" >> /etc/elasticsearch/elasticsearch.yml
echo "discovery.zen.ping.unicast.hosts: $HOSTS_CONFIG" >> /etc/elasticsearch/elasticsearch.yml


# Configure Elasticsearch node type
log "Configure master/client/data node type flags "
log "Configure node for master and data"
echo "node.master: true" >> /etc/elasticsearch/elasticsearch.yml
echo "node.data: true" >> /etc/elasticsearch/elasticsearch.yml

# DNS Retry
echo "options timeout:1 attempts:5" >> /etc/resolvconf/resolv.conf.d/head
resolvconf -u

# Increase maximum mmap count
echo "vm.max_map_count = 262144" >> /etc/sysctl.conf

#"action.disable_delete_all_indices: ${DISABLE_DELETE_ALL}" >> /etc/elasticsearch/elasticsearch.yml
#"action.auto_create_index: ${AUTOCREATE_INDEX}" >> /etc/elasticsearch/elasticsearch.yml

# Configure Environment
#----------------------
#/etc/default/elasticseach
#Update HEAP Size in this configuration or in upstart service
#Set Elasticsearch heap size to 50% of system memory
#TODO: Move this to an init.d script so we can handle instance size increases
ES_HEAP=`free -m |grep Mem | awk '{if ($2/2 >31744)  print 31744;else print $2/2;}'`
log "Configure elasticsearch heap size - $ES_HEAP"
echo "ES_HEAP_SIZE=${ES_HEAP}m" >> /etc/default/elasticsearch

#Optionally Install Marvel
if [ "${INSTALL_MARVEL}" == "yes" ];
    then
    log "Installing Marvel Plugin"
    /usr/share/elasticsearch/bin/plugin -i elasticsearch/marvel/latest
fi

#Optionally Install Kibana
if [ "${INSTALL_KIBANA}" == "yes" ];
  then
    log "Installing Kibana"

    # Import the Elasticsearch public GPG key into apt
    sudo wget -qO - https://packages.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
  
    # Create the Kibana source list
    echo "deb http://packages.elastic.co/kibana/4.5/debian stable main" | sudo tee -a /etc/apt/sources.list
  
    # Update apt package database
    sudo apt-get update
  
    # Install Kibana
    sudo apt-get -y --force-yes install kibana
  
    # Enable the Kibana service and start it
    sudo update-rc.d kibana defaults 95 10
    sudo service kibana start
fi

#and... start the service
log "Starting Elasticsearch on ${HOSTNAME}"
update-rc.d elasticsearch defaults 95 10
sudo service elasticsearch start
log "complete elasticsearch setup and started"

# Install Nginx
bash nginx-ubuntu-install.sh -u $USERNAME -p $PASSWORD

exit 0

#Script Extras

#Configure open file and memory limits
#Swap is disabled by default in Ubuntu Azure VMs
#echo "bootstrap.mlockall: true" >> /etc/elasticsearch/elasticsearch.yml

# Verify this is necessary on azure
#echo "elasticsearch    -    nofile    65536" >> /etc/security/limits.conf
#echo "elasticsearch     -    memlock   unlimited" >> /etc/security/limits.conf
#echo "session    required    pam_limits.so" >> /etc/pam.d/su
#echo "session    required    pam_limits.so" >> /etc/pam.d/common-session
#echo "session    required    pam_limits.so" >> /etc/pam.d/common-session-noninteractive
#echo "session    required    pam_limits.so" >> /etc/pam.d/sudo

#--------------- TEMP (We will use this for the update path yet) ---------------
#Updating the properties in the existing configuraiton has been a bit sensitve and requires more testing
#sed -i -e "/cluster\.name/s/^#//g;s/^\(cluster\.name\s*:\s*\).*\$/\1${CLUSTER_NAME}/" /etc/elasticsearch/elasticsearch.yml
#sed -i -e "/bootstrap\.mlockall/s/^#//g;s/^\(bootstrap\.mlockall\s*:\s*\).*\$/\1true/" /etc/elasticsearch/elasticsearch.yml
#sed -i -e "/path\.data/s/^#//g;s/^\(path\.data\s*:\s*\).*\$/\1${DATAPATH_CONFIG}/" /etc/elasticsearch/elasticsearch.yml

# Minimum master nodes nodes/2+1 (These can be configured via API as well - (_cluster/settings))
# discovery.zen.minimum_master_nodes: 2
# gateway.expected_nodes: 10
# gateway.recover_after_time: 5m
#----------------------
