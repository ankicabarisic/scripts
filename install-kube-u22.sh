#!/bin/bash

# This bash script is designed to prepare and install docker and Kubernetes for Ubuntu 22.04.
# If an error occurs, the script will exit with the value of the PID to point at the logfile.
# Author: Ali Jawad FAHS, Activeeon

# Set up the script variables
STARTTIME=$(date +%s)
PID=$(echo $$)
EXITCODE=$PID
DATE=$(date)
LOGFILE="/var/log/kube-install.$PID.log"

# Set up the logging for the script
sudo touch $LOGFILE
sudo chown $USER:$USER $LOGFILE

# All the output of this shell script is redirected to the LOGFILE
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>$LOGFILE 2>&1

# A function to print a message to stdout as well as the LOGFILE
log_print(){
  level=$1
  Message=$2
  echo "$level [$(date)]: $Message"
  echo "$level [$(date)]: $Message" >&3
}

# A function to check for the apt lock
Check_lock() {
    i=0
    log_print INFO "Checking for apt lock"
    while [ "$(ps aux | grep [l]ock_is_held | wc -l)" != "0" ]; do
        echo "Lock_is_held $i"
        ps aux | grep [l]ock_is_held
        sleep 10
        ((i=i+10))
    done
    log_print INFO "Exited the while loop, time spent: $i"
    ps aux | grep apt
    log_print INFO "Waiting for lock task ended properly."
}

# Start the Configuration
log_print INFO "Configuration started!"
log_print INFO "Logs are saved at: $LOGFILE"

# Update the package list
log_print INFO "Updating the package list."
sudo apt-get update
sudo unattended-upgrade -d

# Check for lock
Check_lock

# Install curl
log_print INFO "Installing curl"
sudo apt-get install -y curl || { log_print ERROR "curl installation failed!"; exit $EXITCODE; }

# Install Docker
log_print INFO "Installing Docker"
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

sudo docker -v || { log_print ERROR "Docker installation failed!"; exit $EXITCODE; }

# Refresh Kubernetes GPG Key
log_print INFO "Refreshing Kubernetes GPG key"
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg || { log_print ERROR "Failed to add Kubernetes GPG key"; exit $EXITCODE; }

# Update Kubernetes repository configuration
log_print INFO "Updating Kubernetes repository configuration"
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Check for lock
Check_lock

# Update package list after repository update
sudo apt-get update

# Check for lock
Check_lock

# Install specific version of Kubernetes
log_print INFO "Installing Kubernetes version 1.26.15"
sudo apt-get install -y kubeadm=1.26.15-00 kubelet=1.26.15-00 kubectl=1.26.15-00 --allow-downgrades || { log_print ERROR "Kubernetes installation failed!"; exit $EXITCODE; }

# Hold Kubernetes versions to prevent auto-updates
sudo apt-mark hold kubeadm kubelet kubectl

# Configure containerd
log_print INFO "Configuring containerd"
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# Check Kubernetes versions
log_print INFO "Checking Kubernetes versions"
kubeadm version || { log_print ERROR "kubeadm check failed!"; exit $EXITCODE; }
kubectl version || { log_print ERROR "kubectl check failed!"; exit $EXITCODE; }
kubelet --version || { log_print ERROR "kubelet check failed!"; exit $EXITCODE; }

# Disable swap memory if not already disabled
if [ "$(grep Swap /proc/meminfo | grep SwapTotal: | awk '{print $2}')" -ne "0" ]; then
    log_print INFO "Disabling swap memory"
    sudo swapoff -a || { log_print ERROR "Failed to turn off swap memory"; exit $EXITCODE; }
else
    log_print INFO "Swap memory is already off"
fi

# Declare configuration completed successfully
ENDTIME=$(date +%s)
ELAPSED=$(( ENDTIME - STARTTIME ))
log_print INFO "Configuration done successfully in $ELAPSED seconds"
