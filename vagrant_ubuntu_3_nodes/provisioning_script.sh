#!/bin/bash

echo "hello"

function common_tools {
# bridged traffic to iptables is enabled for kube-router.
cat >> /etc/ufw/sysctl.conf << EOF
net/bridge/bridge-nf-call-ip6tables = 1
net/bridge/bridge-nf-call-iptables = 1
net/bridge/bridge-nf-call-arptables = 1
EOF

swapoff -a
sed -i '/swap/d' /etc/fstab

export DEBIAN_FRONTEND=noninteractive
apt-get install curl 

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y git ebtables ethtool apt-transport-https docker.io
apt-get install -y kubelet kubeadm kubectl
}

function provision_cri {
# Install GO and cri###
git clone https://github.com/Mirantis/cri-dockerd.git --progress
wget https://storage.googleapis.com/golang/getgo/installer_linux
chmod +x ./installer_linux
./installer_linux
source ~/.bash_profile
cd cri-dockerd
mkdir bin
go build -o bin/cri-dockerd
mkdir -p /usr/local/bin
install -o root -g root -m 0755 bin/cri-dockerd /usr/local/bin/cri-dockerd
cp -a packaging/systemd/* /etc/systemd/system
sed -i -e 's,/usr/bin/cri-dockerd,/usr/local/bin/cri-dockerd,' /etc/systemd/system/cri-docker.service
systemctl daemon-reload
systemctl enable cri-docker.service
systemctl enable --now cri-docker.socket
# remove above if fails
}
  
function provision_master_node {
# creating join.sh script which can be accessible and executed by worker nodes
OUTPUT_FILE=/vagrant/join.sh
rm -rf $OUTPUT_FILE
# initialize master node
sudo kubeadm init --apiserver-advertise-address=192.168.56.11 --pod-network-cidr=10.244.0.0/16 --cri-socket=unix:///var/run/cri-dockerd.sock| grep "kubeadm join" > ${OUTPUT_FILE}
# appending join.sh script with cri socket and skiping verification
echo "--cri-socket=unix:///var/run/cri-dockerd.sock \" >> $OUTPUT_FILE
echo "--discovery-token-unsafe-skip-ca-verification \" >>  $OUTPUT_FILE
chmod +x $OUTPUT_FILE
# Configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
# Fix kubelet IP
echo 'Environment="KUBELET_EXTRA_ARGS=--node-ip=192.168.56.11"' | sudo tee -a /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
}
  
function install_flannel {
# flannel required for networking in k8s cluster
wget https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
kubectl apply -f kube-flannel.yml
sudo systemctl daemon-reload
sudo systemctl restart kubelet
kubectl taint nodes master node-role.kubernetes.io/control-plane-
}

function joinworker {  
# executing joining script created on master node and accessible via shared folder /vagrant/ which is available on all hosts (master and workers)
sh /vagrant/join.sh
systemctl daemon-reload
systemctl restart kubelet
 
}

sudo common_tools
