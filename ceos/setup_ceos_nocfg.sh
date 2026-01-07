#!/bin/bash

# 1. Setup Networks
docker network create --subnet=192.168.20.0/24 client
docker network create --subnet=10.20.0.0/16 kind01
docker network create --subnet=172.20.0.0/16 kind02

# 2. Start Container (Connects eth0/Ethernet1 automatically via --network)
docker run -itd --name=ceos-r1 --privileged \
  --network client --ip 192.168.20.101 \
  -e INTFTYPE=eth -e ETBA=4 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 \
  -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=docker \
  snpsuen/ceos:4.33 \
  /sbin/init \
  systemd.setenv=INTFTYPE=eth \
  systemd.setenv=ETBA=4 \
  systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 \
  systemd.setenv=CEOS=1 \
  systemd.setenv=EOS_PLATFORM=ceoslab \
  systemd.setenv=container=docker

# 3. Connect remaining networks BEFORE configuring
docker network connect --ip 10.20.0.101 kind01 ceos-r1
docker network connect --ip 172.20.0.101 kind02 ceos-r1

# 4. Give the agents a moment to see the new interfaces
echo "Waiting 20s for interfaces to initialize..."
sleep 20
docker exec ceos-r1 ip -4 addr
