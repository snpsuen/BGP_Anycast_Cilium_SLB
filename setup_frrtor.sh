
#!/bin/bash

docker network create --subnet=192.168.20.0/24 client
docker run -d --init --privileged --name frrtor \
-v ./configure/frrtor.conf:/etc/frr/frr.conf \
-v ./configure/frrdaemons:/etc/frr/daemons \
-v ./configure/vtysh.conf:/etc/frr/vtysh.conf \
--network client --ip 192.168.20.101 \
frrouting/frr:latest

docker network connect --ip 10.20.0.101 kind01 frrtor
docker network connect --ip 172.20.0.101 kind02 frrtor

docker exec frrtor sh -c "sysctl -w net.ipv4.ip_forward=1 && sysctl -w net.ipv4.fib_multipath_hash_policy=1"
docker exec frrtor vtysh -c "show interface && show running-config"
docker exec frrtor vtysh -c "show bgp summary && show ip bgp && show ip route"
