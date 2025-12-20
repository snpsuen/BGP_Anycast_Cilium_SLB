#!/bin/bash

kind=$1
if [ -z "$kind" ]
then
  kind="kind01"
fi

if [ $kind == "kind01" ]
then
  sudo sysctl -w fs.inotify.max_user_watches=524288
  sudo sysctl -w fs.inotify.max_user_instances=512

  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

  [ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
  chmod u+x ./kind
  cp -p ./kind /usr/local/bin
fi

if [ $kind == "kind01" ]
then
  kindsubnet="10.20.0.0/16"
  kindgw="10.20.0.101"
fi

if [ $kind == "kind02" ]
then
  kindsubnet="172.20.0.0/16"
  kindgw="172.20.0.101"
fi

docker network create --subnet=$kindsubnet $kind
export KIND_EXPERIMENTAL_DOCKER_NETWORK=$kind
kind create cluster --config=- <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $kind
nodes:
 - role: control-plane
 - role: worker
EOF

docker exec ${kind}-control-plane ip route add 192.168.20.0/24 via $kindgw dev eth0
docker exec ${kind}-worker ip route add 192.168.20.0/24 via $kindgw dev eth0

docker exec ${kind}-control-plane bash -c "apt-get update && apt-get install iputils-ping"
docker exec ${kind}-worker bash -c "apt-get update && apt-get install iputils-ping"

kubectl get nodes -o wide
kubectl taint nodes ${kind}-control-plane node-role.kubernetes.io/control-plane:NoSchedule-
kubectl describe node ${kind}-worker | grep Taints

kubectl delete daemonset -n kube-system kube-proxy
docker exec ${kind}-control-plane rm -rf /etc/cni/net.d/*
docker exec ${kind}-worker rm -rf /etc/cni/net.d/*

if [ $kind == "kind01" ]
then
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  CLI_ARCH=amd64
  if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
  curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
  sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
  sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
  rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
fi

cilium install \
  --set kubeProxyReplacement="true" \
  --set routingMode="native" \
  --set ipv4NativeRoutingCIDR="10.244.0.0/16" \
  --set bgpControlPlane.enabled=true \
  --set l2NeighDiscovery.enabled=true \
  --set l2announcements.enabled=true \
  --set l2podAnnouncements.enabled=true \
  --set externalIPs.enabled=true \
  --set autoDirectNodeRoutes=true \
  --set operator.replicas=2
