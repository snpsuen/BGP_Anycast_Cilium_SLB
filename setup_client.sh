#!/bin/bash

docker run -d --privileged --name client --network client ghcr.io/hellt/network-multitool sleep infinity
docker exec client sh -c "ip route add 10.20.0.0/16 via 192.168.20.101 dev eth0 && ip route add 172.20.0.0/16 via 192.168.20.101 dev eth0"
docker exec client ip route add 172.30.0.0/16 via 192.168.20.101 dev eth0
