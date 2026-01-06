#!/bin/bash

docker network create --subnet=192.168.20.0/24 client
docker network create --subnet=10.20.0.0/16 kind01
docker network create --subnet=172.20.0.0/16 kind02

#!/bin/bash

# ... network creation ...

# Using 'EOF' prevents Bash from interpreting any characters inside the config
cat > ceos1.cfg <<'EOF'
! Arista cEOS Configuration
hostname ceos-r1
ip routing

! 1. DEFINE FILTERS FIRST (Dependency Order)
ip prefix-list ANYCAST_ONLY
   seq 10 permit 172.30.0.10/32

route-map RM-ADD-PATH-SELECTION permit 10
   match ip address prefix-list ANYCAST_ONLY

route-map ACCEPT-ALL permit 10

! 2. INTERFACES
interface Ethernet1
   no switchport
   ip address 192.168.20.101/24
interface Ethernet2
   no switchport
   ip address 10.20.0.101/16
interface Ethernet3
   no switchport
   ip address 172.20.0.101/16

! 3. ROUTING
router bgp 65001
   router-id 10.0.255.11
   bgp bestpath as-path multipath-relax
   !
   address-family ipv4
      bgp additional-paths install
      bgp additional-paths selection route-map RM-ADD-PATH-SELECTION
      maximum-paths 10
      network 192.168.20.0/24
      network 10.20.0.0/16
      network 172.20.0.0/16
      !
      neighbor 10.20.0.2 remote-as 65101
      neighbor 10.20.0.2 additional-paths receive
      neighbor 10.20.0.2 additional-paths send any
      neighbor 10.20.0.2 advertise additional-paths route-map RM-ADD-PATH-SELECTION
      neighbor 10.20.0.2 route-map ACCEPT-ALL out
      ! (Repeat for other neighbors...)
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
