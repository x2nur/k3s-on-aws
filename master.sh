#!/bin/bash

apt update
apt install -y curl
curl -sfL https://get.k3s.io | K3S_TOKEN=$1 K3S_NODE_NAME=$2 sh -
