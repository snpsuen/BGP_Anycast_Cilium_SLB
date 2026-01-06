#!/bin/bash

docker network create --subnet=192.168.20.0/24 client
docker network create --subnet=10.20.0.0/16 kind01
docker network create --subnet=172.20.0.0/16 kind02

cat > ceos1.cfg <<EOF
! Arista cEOS Configuration
hostname ceos-r1

ip routing

! Interfaces eth1-3
interface Ethernet1
   no switchport
   ip address 192.168.20.101/24
interface Ethernet2
   no switchport
   ip address 10.20.0.101/16
interface Ethernet3
   no switchport
   ip address 172.20.0.101/16

! --- FILTERS ---
ip prefix-list ANYCAST_ONLY
   seq 10 permit 172.30.0.10/32

route-map RM-ADD-PATH-SELECTION permit 10
   match ip address prefix-list ANYCAST_ONLY

route-map ACCEPT-ALL permit 10
! ---

router bgp 65001
   router-id 10.0.255.11
   bgp bestpath as-path multipath-relax
   
   address-family ipv4
      bgp additional-paths install
      bgp additional-paths selection route-map RM-ADD-PATH-SELECTION
      maximum-paths 10
      
      network 192.168.20.0/24
      network 10.20.0.0/16
      network 172.20.0.0/16

      ! Neighbor AS 65101 Example (Apply to all)
      neighbor 10.20.0.2 remote-as 65101
      neighbor 10.20.0.2 additional-paths receive
      neighbor 10.20.0.2 additional-paths send any
      ! This next line is the key fix:
      neighbor 10.20.0.2 advertise additional-paths route-map RM-ADD-PATH-SELECTION
      neighbor 10.20.0.2 route-map ACCEPT-ALL out
      
      ! ... repeat pattern for 10.20.0.3, 172.20.0.2, 172.20.0.3 ...
      neighbor 10.20.0.3 remote-as 65101
      neighbor 10.20.0.3 additional-paths receive
      neighbor 10.20.0.3 additional-paths send any
      ! This next line is the key fix:
      neighbor 10.20.0.3 advertise additional-paths route-map RM-ADD-PATH-SELECTION
      neighbor 10.20.0.3 route-map ACCEPT-ALL out
	  
	  neighbor 172.20.0.2 remote-as 65102
      neighbor 172.20.0.2 additional-paths receive
      neighbor 172.20.0.2 additional-paths send any
      ! This next line is the key fix:
      neighbor 172.20.0.2 advertise additional-paths route-map RM-ADD-PATH-SELECTION
      neighbor 172.20.0.2 route-map ACCEPT-ALL out

	  neighbor 172.20.0.3 remote-as 65102
      neighbor 172.20.0.3 additional-paths receive
      neighbor 172.20.0.3 additional-paths send any
      ! This next line is the key fix:
      neighbor 172.20.0.3 advertise additional-paths route-map RM-ADD-PATH-SELECTION
      neighbor 172.20.0.3 route-map ACCEPT-ALL out
EOF

docker run -itd --name=ceos-r1 --privileged \
  --network client --ip 192.168.20.101 \
  -v $(pwd)/ceos1.cfg:/mnt/flash/startup-config:rw \
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

docker network connect --ip 10.20.0.101 kind01 ceos-r1
docker network connect --ip 172.20.0.101 kind02 ceos-r1

docker exec frrtor vtysh -c "show bgp summary && show ip bgp && show ip route"
