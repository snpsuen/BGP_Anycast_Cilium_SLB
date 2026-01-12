#!/bin/bash

docker network create --subnet=192.168.20.0/24 client

mkdir -p configure
cat > configure/frrtor.conf <<EOF
interface eth0
 ip address 192.168.20.101/24
interface eth1
 ip address 10.20.0.101/16
interface eth2
 ip address 172.20.0.101/16
!
router bgp 65001
 bgp router-id 10.0.255.11
 bgp bestpath as-path multipath-relax
 neighbor 10.20.0.2 remote-as 65101
 neighbor 10.20.0.3 remote-as 65101
 neighbor 172.20.0.2 remote-as 65102
 neighbor 172.20.0.3 remote-as 65102
 !
 address-family ipv4 unicast
  maximum-paths 10
  network 192.168.20.0/24
  network 10.20.0.0/16
  network 172.20.0.0/16
  
  neighbor 10.20.0.2 route-map ACCEPT-ALL in
  neighbor 10.20.0.2 route-map ACCEPT-ALL out
  neighbor 10.20.0.3 route-map ACCEPT-ALL in
  neighbor 10.20.0.3 route-map ACCEPT-ALL out
  neighbor 172.20.0.2 route-map ACCEPT-ALL in
  neighbor 172.20.0.2 route-map ACCEPT-ALL out
  neighbor 172.20.0.3 route-map ACCEPT-ALL in
  neighbor 172.20.0.3 route-map ACCEPT-ALL out
 exit-address-family
!
route-map ACCEPT-ALL permit 10
EOF

cat > configure/frrdaemons <<EOF
zebra=yes
bgpd=yes
staticd=yes
ospfd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
EOF

cat > configure/vtysh.conf <<EOF
service integrated-vtysh-config
EOF

docker run -d --init --privileged --name frrtor \
-v ./configure/frrtor_addpath.conf:/etc/frr/frr.conf \
-v ./configure/frrdaemons:/etc/frr/daemons \
-v ./configure/vtysh.conf:/etc/frr/vtysh.conf \
--network client --ip 192.168.20.101 \
frrouting/frr:latest

docker network connect --ip 10.20.0.101 kind01 frrtor
docker network connect --ip 172.20.0.101 kind02 frrtor

docker exec frrtor sh -c "sysctl -w net.ipv4.ip_forward=1 && sysctl -w net.ipv4.fib_multipath_hash_policy=1"
docker exec frrtor vtysh -c "show interface && show running-config"
docker exec frrtor vtysh -c "show bgp summary && show ip bgp && show ip route"
