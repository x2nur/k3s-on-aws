#!/bin/bash

apt update
apt install -y curl
curl -sfL https://get.k3s.io | K3S_URL=https://$1:6443 K3S_TOKEN=$2 K3S_NODE_NAME=$3 sh -
