![BGP_anycast_cilium](bgp_anycast_cilium.png)

In this exercise, we will build and experiment with BGP anyscast routes that steer client requests to a service VIP advertised by the Cilium CNI provider from two Kubernetes clusters. The work will be carried out in a nifty but realistic emulation lab where all the assets including the FRR switch container and kind K8s clusters are deployed by hand.

### Why does it matter?

As Cilium is becoming the CNI of choice for Kubernetes, we hope to devise a golden template for users to configure the Cilium BGP control plane in a standard way for Kubernetes service load balancing. It also caters for the configuration of an FRR router as a typical upstream BGP neigbour to interact with Cilium on two or more Kubernetes clusters. 

All in all, what we are going to do here is ready to extend to more sophisticated use cases of applying global server load balancing (GSLB) at scale to numerous Kubernetes services or ingress gateways that spring up on cloud or on premises nowadays.

### Lab inventory

Our lab provides an emulation enviroment for the docker resources below to constitute the underlying topology. All of them are deployed by hand on an Ubuntu VM host.

<table>
	<thead>
		<tr>
			<th scope="col">Topology Node</th>
			<th scope="col">Docker Type</th>
			<th scope="col">Network Configuration</th>
			<th scope="col">Creation</th>
		</tr>
	</thead>
	<tbody>
		<tr>
			<td aligh="left">Client workstation</td>
			<td aligh="left">Container</td>
			<td aligh="left">192.168.20.2/24</td>
			<td aligh="left">docker run</td>
		</tr>
        <tr>
			<td aligh="left">Client docker subnet</td>
			<td aligh="left">Network</td>
			<td aligh="left">192.168.20.0/24</td>
			<td aligh="left">docker network create</td>
		</tr>
		<tr>
			<td aligh="left">FRR tor switch</td>
			<td aligh="left">Container</td>
			<td aligh="left">192.168.20.101/24 <br>
                10.20.0.101/16 <br>
				172.20.0.101/16 <br>
				BGP ASN: 65001
			</td>
			<td aligh="left">docker run</td>
		</tr>
        <tr>
			<td aligh="left">Kind01 K8s cluster node 1</td>
			<td aligh="left">Container</td>
			<td aligh="left">10.20.0.2/16</td>
			<td aligh="left">kind create cluster</td>
		</tr>
		<tr>
			<td aligh="left">Kind01 K8s cluster node 2</td>
			<td aligh="left">Container</td>
			<td aligh="left">10.20.0.3/16</td>
			<td aligh="left">kind create cluster</td>
		</tr>
		 <tr>
			<td aligh="left">Kind01 docker subnet</td>
			<td aligh="left">Network</td>
			<td aligh="left">10.20.0.0/16</td>
			<td aligh="left">docker network create</td>
		</tr>
		 <tr>
			<td aligh="left">Kind02 K8s cluster node 1</td>
			<td aligh="left">Container</td>
			<td aligh="left">172.20.0.2/16</td>
			<td aligh="left">kind create cluster</td>
		</tr>
		<tr>
			<td aligh="left">Kind02 K8s cluster node 2</td>
			<td aligh="left">Container</td>
			<td aligh="left">172.20.0.3/16</td>
			<td aligh="left">kind create cluster</td>
		</tr>
		 <tr>
			<td aligh="left">Kind02 docker subnet</td>
			<td aligh="left">Network</td>
			<td aligh="left">172.20.0.0/16</td>
			<td aligh="left">kind create cluster</td>
		</tr>
  </tbody>
</table>

### 1. Deploy the kind Kubernetes clusters

The lab is assumed to take place in a Ubuntu 22.04 VM host on VirtualBox in our example. <br>
Install the Kind binaries on the host.
```
sudo sysctl -w fs.inotify.max_user_watches=524288
sudo sysctl -w fs.inotify.max_user_instances=512

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
chmod u+x ./kind
cp -p ./kind /usr/local/bin
```

Create a docker subnet named kind01 with a cidr of 10.20.0.0/16. <br>
Set the environment variable KIND_EXPERIMENTAL_DOCKER_NETWORK to kind01 to instruct kind to create the first Kubernetes cluster called kind01 on the the user defined subnet 10.20.0.0/16
```
docker network create --subnet=10.20.0.0/16 kind01
export KIND_EXPERIMENTAL_DOCKER_NETWORK=kind01
kind create cluster --config=- <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: kind01
nodes:
 - role: control-plane
 - role: worker
EOF
```

Perform post-deployment routines on the kind cluster nodes by adding the return routes for the client network and installing auxilliary utilities.
```
docker exec kind01-control-plane ip route add 192.168.20.0/24 via 10.20.0.101 dev eth0
docker exec kind01-worker ip route add 192.168.20.0/24 via 10.20.0.101 dev eth0

docker exec kind01-control-plane bash -c "apt-get update && apt-get install iputils-ping"
docker exec kind01-worker bash -c "apt-get update && apt-get install iputils-ping"
```

After installation, the kubectl context points to the newly created Kubernetes cluster, kind01.
```
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl config current-context
kind-kind01
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl get nodes -o wide
NAME                   STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION       CONTAINER-RUNTIME
kind01-control-plane   Ready    control-plane   8m17s   v1.34.0   10.20.0.3     <none>        Debian GNU/Linux 12 (bookworm)   5.15.0-156-generic   containerd://2.1.3
kind01-worker          Ready    <none>          7m51s   v1.34.0   10.20.0.2     <none>        Debian GNU/Linux 12 (bookworm)   5.15.0-156-generic   containerd://2.1.3
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$
```

Similarly use kind to create the second Kubernetes cluster called kind02 on the the user defined subnet 172.20.0.0/16.
```
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl config current-context
kind-kind02
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl get nodes -o wide
NAME                   STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION       CONTAINER-RUNTIME
kind02-control-plane   Ready    control-plane   2m32s   v1.34.0   172.20.0.2    <none>        Debian GNU/Linux 12 (bookworm)   5.15.0-156-generic   containerd://2.1.3
kind02-worker          Ready    <none>          2m12s   v1.34.0   172.20.0.3    <none>        Debian GNU/Linux 12 (bookworm)   5.15.0-156-generic   containerd://2.1.3
```

### 2. Install Cilum in Kubernetes

Before installation, it is necessary to remove the default CNI that comes with kind together with the kube-proxy and kindnet daemon sets.
```
kubectl delete daemonset -n kube-system kube-proxy
kubectl delete daemonset -n kube-system kindnet
docker exec kind01-control-plane rm -rf /etc/cni/net.d/*
docker exec kind01-worker rm -rf /etc/cni/net.d/*
```

Install Cilium in both K8s clusters with the desirable settings. In particular, the flag bgpControlPlane.enabled=true means the Cilium BGP control plane will be enabled upon installation.
```
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

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
```

Check the installation completed OK and Cilium has taken over each cluster.
```
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ cilium status
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       disabled
    \__/       ClusterMesh:        disabled

DaemonSet              cilium                   Desired: 2, Ready: 2/2, Available: 2/2
DaemonSet              cilium-envoy             Desired: 2, Ready: 2/2, Available: 2/2
Deployment             cilium-operator          Desired: 2, Ready: 2/2, Available: 2/2
Containers:            cilium                   Running: 2
                       cilium-envoy             Running: 2
                       cilium-operator          Running: 2
                       clustermesh-apiserver
                       hubble-relay
Cluster Pods:          4/5 managed by Cilium
Helm chart version:    1.18.3
Image versions         cilium             quay.io/cilium/cilium:v1.18.3@sha256:5649db451c88d928ea585514746d50d91e6210801b300c897283ea319d68de15: 2
                       cilium-envoy       quay.io/cilium/cilium-envoy:v1.34.10-1761014632-c360e8557eb41011dfb5210f8fb53fed6c0b3222@sha256:ca76eb4e9812d114c7f43215a742c00b8bf41200992af0d21b5561d46156fd15: 2
                       cilium-operator    quay.io/cilium/operator-generic:v1.18.3@sha256:b5a0138e1a38e4437c5215257ff4e35373619501f4877dbaf92c89ecfad81797: 2
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl -n kube-system get pods
NAME                                           READY   STATUS    RESTARTS   AGE
cilium-42gvd                                   1/1     Running   0          27m
cilium-792kd                                   1/1     Running   0          27m
cilium-envoy-dqppr                             1/1     Running   0          27m
cilium-envoy-hwbwr                             1/1     Running   0          27m
cilium-operator-686595b9d4-hnmpw               1/1     Running   0          27m
cilium-operator-686595b9d4-mt7sm               1/1     Running   0          27m
coredns-66bc5c9577-vwkmq                       1/1     Running   0          26m
coredns-66bc5c9577-zfjh6                       1/1     Running   0          26m
etcd-kind01-control-plane                      1/1     Running   0          28m
kube-apiserver-kind01-control-plane            1/1     Running   0          28m
kube-controller-manager-kind01-control-plane   1/1     Running   0          28m
kube-scheduler-kind01-control-plane            1/1     Running   0          28m
```

### 3. Deploy FRR switch

Deploy an FRR switch container go perform the role of a so-called top of the rack router and forward traffic between the two kind clusters and client.
In this example, the switch is connected to the following IP subnets.
* client: 192.168.20.0/24
* kind01: 10.20.0.0/16
* kind02: 172.20.0.0/16
  
```
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
```

The FRR switch is configured by virtue of these files mounted on /etc/frr within the container.
* [configure/frrtor.conf](configure/frrtor.conf)
* [configure/frrdaemons](configure/frrdaemons)
* [configure/vtysh.conf](configure/vtysh.conf)

In particular, it is important to turn on the following bgp features as per [frrtor.conf](configure/frrtor.conf), which are pivotal to the adoption of ECMP routes.
```
bgp bestpath as-path multipath-relax
...
maximum-paths 10
```

The first line means that the switch will treat two or more BGP routes whose AS paths are of the same length as equal-cost routes. In our example, the AS path of the BGP route to the anycast VIP on the kind01 cluster is "65101 i", while the BGP route to the anycast VIP on kind02 takes the AS path "65102 i". The routes are considered equal in cost as both are two ASNs long.

The second line indicates that the switch will install a maximum of 10 equal-cost routes as ECMP routes.

Another point of note is to set following net.ipv4 parameter when frrtor comes up.
```
sysctl -w net.ipv4.fib_multipath_hash_policy=1
```

It means the switch will hash the L4 headers of an connection flow in the form of a 5-tuple to determine which ECMP route to take. Accordingly, connection flows that are different in the fields of source port, source IP, destimation port and destination IP tend to be assigned different ECMP routes.

### 4. Get ready for Cilium service load balancing

Define a load balancing IP address management pool (LB IPAM) from which to assign IP addresses to Kubernetes services of the LoadBalancer type. In our example, the pool ranges from "172.30.0.10" to "172.30.0.20".

Apply the given manifest [kind-lbippool.yaml](manifests/kind-lbippool.yaml) in each kind cluster.
```
kubectl apply -f kind-lbippool.yaml
```

Configure the Cilum BGP control plane for each kind cluster to advertise the LoadBalancer IP of the selected service to the upstream BGP peer at frrtor. Note the settings are specified on a per service label basis.
<table>
	<thead>
		<tr>
			<th scope="col">Kind K8s cluster</th>
			<th scope="col">Local ASN</th>
			<th scope="col">Peer ASN</th>
			<th scope="col">BGP peer</th>
			<th scope="col">Advertisement Resource</th>
			<th scope="col">Advertisement Address Type</th>
			<th scope="col">Service Label</th>
			<th scope="col">LB IPAM Pool</th>
		</tr>
	</thead>
	<tbody>
		<tr>
			<td aligh="left">kind01</td>
			<td aligh="left">65101</td>
			<td aligh="left">65001</td>
			<td aligh="left">10.20.0.101</td>
			<td aligh="left">Service</td>
			<td aligh="left">LoadBalancer IP</td>
			<td aligh="left">lbmode: bgp</td>
			<td aligh="left">172.30.0.10-172.30.0.20</td>
		</tr>
		<tr>
			<td aligh="left">kind02</td>
			<td aligh="left">65102</td>
			<td aligh="left">65001</td>
			<td aligh="left">172.20.0.101</td>
			<td aligh="left">Service</td>
			<td aligh="left">LoadBalancer IP</td>
			<td aligh="left">lbmode: bgp</td>
			<td aligh="left">172.30.0.10-172.30.0.20</td>
		</tr>
	</tbody>
</table>

The configuration is done by appling the following manifests to create the relevant Cilum custom resources on each kind cluster.
* [kind-bgp-peer.yaml](manifests/kind-bgp-peer.yaml)
* [kind01-bgp-cluster.yaml](manifests/kind01-bgp-cluster.yaml) or [kind02-bgp-cluster.yaml](manifests/kind02-bgp-cluster.yaml)
* [kind-bgp-advertisements.yaml](manifests/kind-bgp-advertisements.yaml)

```
kubectl apply -f kind-bgp-peer.yaml

# kindcluster variable is set to "kind01" or "kind02" somehere in advance
if [ $kindcluster == "kind01" ]
then
  kubectl apply -f kind01-bgp-cluster.yaml
fi
if [ $kindcluster == "kind02" ]
then
  kubectl apply -f kind02-bgp-cluster.yaml
fi

kubectl apply -f kind-bgp-advertisements.yaml
```

### 5. Deploy Nginx for test

Deploy a [nginx service](manifests/nginxhello.yaml) together with its endpoint pods in each kind cluster. 
Note that the service is of the LoadBalancer type and labelled with lbmod: bgp. Accordingly, it will be assigned an IP from the LB IPAM pool and handled by the Cilum BGP control plane for the purpose of service load balancing.
```
kubectl appply -f nginxhello.yaml
```

As expected, the nginx service is assigned an VIP 172.30.0.10, which becomes an anycast IP as it is used to expose the pods running in different kind clusters.
```
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl config use-context kind-kind01
Switched to context "kind-kind01".
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl get svc
NAME         TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
kubernetes   ClusterIP      10.96.0.1      <none>        443/TCP        11h
nginxhello   LoadBalancer   10.96.138.62   172.30.0.10   80:31365/TCP   7h55m
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl get pods -o wide
NAME                          READY   STATUS    RESTARTS   AGE     IP             NODE                   NOMINATED NODE   READINESS GATES
nginxhello-85f8846c44-kb44r   1/1     Running   0          7h55m   10.244.1.171   kind01-worker          <none>           <none>
nginxhello-85f8846c44-pzpzs   1/1     Running   0          7h55m   10.244.0.56    kind01-control-plane   <none>           <none>
```

```
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl config use-context kind-kind02
Switched to context "kind-kind02".
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl get svc
NAME         TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
kubernetes   ClusterIP      10.96.0.1      <none>        443/TCP        10h
nginxhello   LoadBalancer   10.96.149.92   172.30.0.10   80:31764/TCP   7h58m
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl get pods -o wide
NAME                          READY   STATUS    RESTARTS   AGE     IP             NODE                   NOMINATED NODE   READINESS GATES
nginxhello-85f8846c44-v88f8   1/1     Running   0          7h58m   10.244.0.190   kind02-control-plane   <none>           <none>
nginxhello-85f8846c44-vtgtz   1/1     Running   0          7h58m   10.244.1.247   kind02-worker          <none>           <none>
```

Check that the following routes to the anycast VIP 172.30.0.10/32 are admitted into the BGP Loc-RIB and installed as ECMP routes on frrtor.
<table>
	<thead>
		<tr>
			<th scope="col">Prefix</th>
			<th scope="col">Next hop</th>
			<th scope="col">AS Path</th>
			<th scope="col">Workload destination</th>
		</tr>
	</thead>
	<tbody>
		<tr>
			<td aligh="left">172.30.0.10/32</td>
			<td aligh="left">10.20.0.2</td>
			<td aligh="left">65101 i</td>
			<td aligh="left">kind01</td>
		</tr>
		<tr>
			<td aligh="left">172.30.0.10/32</td>
			<td aligh="left">10.20.0.3</td>
			<td aligh="left">65101 i</td>
			<td aligh="left">kind01</td>
		</tr>
		<tr>
			<td aligh="left">172.30.0.10/32</td>
			<td aligh="left">172.20.0.2</td>
			<td aligh="left">65102 i</td>
			<td aligh="left">kind02</td>
		</tr>
		<tr>
			<td aligh="left">172.30.0.10/32</td>
			<td aligh="left">172.20.0.3</td>
			<td aligh="left">65102 i</td>
			<td aligh="left">kind02</td>
		</tr>
	</tbody>
</table>

```
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ docker exec frrtor vtysh -c "show ip bgp"
BGP table version is 6, local router ID is 10.0.255.11, vrf id 0
Default local pref 100, local AS 65001
Status codes:  s suppressed, d damped, h history, * valid, > best, = multipath,
               i internal, r RIB-failure, S Stale, R Removed
Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
Origin codes:  i - IGP, e - EGP, ? - incomplete
RPKI validation codes: V valid, I invalid, N Not found

   Network          Next Hop            Metric LocPrf Weight Path
*> 10.20.0.0/16     0.0.0.0                  0         32768 i
*= 10.96.138.62/32  10.20.0.3                              0 65101 i
*>                  10.20.0.2                              0 65101 i
*> 10.96.149.92/32  172.20.0.2                             0 65102 i
*=                  172.20.0.3                             0 65102 i
*> 172.20.0.0/16    0.0.0.0                  0         32768 i
*= 172.30.0.10/32   10.20.0.3                              0 65101 i
*=                  10.20.0.2                              0 65101 i
*>                  172.20.0.2                             0 65102 i
*=                  172.20.0.3                             0 65102 i
*> 192.168.20.0/24  0.0.0.0                  0         32768 i

Displayed  6 routes and 11 total paths
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ docker exec frrtor vtysh -c "show ip route"
Codes: K - kernel route, C - connected, S - static, R - RIP,
       O - OSPF, I - IS-IS, B - BGP, E - EIGRP, N - NHRP,
       T - Table, v - VNC, V - VNC-Direct, A - Babel, F - PBR,
       f - OpenFabric,
       > - selected route, * - FIB route, q - queued, r - rejected, b - backup
       t - trapped, o - offload failure

K>* 0.0.0.0/0 [0/0] via 192.168.20.1, eth0, 01:51:10
C>* 10.20.0.0/16 is directly connected, eth1, 01:51:10
B>* 10.96.138.62/32 [20/0] via 10.20.0.2, eth1, weight 1, 01:29:11
  *                        via 10.20.0.3, eth1, weight 1, 01:29:11
B>* 10.96.149.92/32 [20/0] via 172.20.0.2, eth2, weight 1, 01:31:34
  *                        via 172.20.0.3, eth2, weight 1, 01:31:34
C>* 172.20.0.0/16 is directly connected, eth2, 01:51:10
B>* 172.30.0.10/32 [20/0] via 10.20.0.2, eth1, weight 1, 01:29:11
  *                       via 10.20.0.3, eth1, weight 1, 01:29:11
  *                       via 172.20.0.2, eth2, weight 1, 01:29:11
  *                       via 172.20.0.3, eth2, weight 1, 01:29:11
C>* 192.168.20.0/24 is directly connected, eth0, 01:51:10
```

### End to end test from client to service

Now we are ready to test the effectiveness of the BGP anycast routes to distribute the workloads of the Nginx service in a load balancing manner. To this end, run a client container on a docker image and launch a suitable command or application from there to access the service. In our example, we choose the network tooling image network-multitool to run the client container.
```
docker run -d --privileged --name client --network client ghcr.io/hellt/network-multitool sleep infinity
docker exec client sh -c "ip route add 10.20.0.0/16 via 192.168.20.101 dev eth0 && ip route add 172.20.0.0/16 via 192.168.20.101 dev eth0"
docker exec client ip route add 172.30.0.0/16 via 192.168.20.101 dev eth0
```

As the Nginx service is addressed at the anycast IP 172.30.0.10, any HTTP request destined to it is expected to land at one of the pods hosted in kind01 or kind02.
<table>
	<thead>
		<tr>
			<th scope="col">Kind cluster</th>
			<th scope="col">Pod</th>
			<th scope="col">Local IP</th>
		</tr>
	</thead>
	<tbody>
		<tr>
			<td aligh="left">kind01</td>
			<td aligh="left">nginxhello-85f8846c44-kb44r</td>
			<td aligh="left">10.244.1.171</td>
		</tr>
		<tr>
			<td aligh="left">kind01</td>
			<td aligh="left">nginxhello-85f8846c44-pzpzs</td>
			<td aligh="left">10.244.0.56</td>
		</tr>
		<tr>
			<td aligh="left">kind02</td>
			<td aligh="left">nginxhello-85f8846c44-v88f8</td>
			<td aligh="left">10.244.0.190</td>
		</tr>
		<tr>
			<td aligh="left">kind02</td>
			<td aligh="left">nginxhello-85f8846c44-vtgtz</td>
			<td aligh="left">10.244.1.247</td>
		</tr>
	</tbody>
</table>

Invoke a simple curl command to the service VIP, namely curl -s http://172.30.0.10, in a loop and keep track of which endpoint pod responds to the HTTP request.
It is observed from the command output that the HTTP traffic is distributed between the nginx pods (10.244.0.171, 10.244.0.56) on kind01 and those (10.244.0.190, 10.244.0.247) on kind02 in a fairly even manner.
```
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ for i in {1..20}
do
docker exec client curl -s http://172.30.0.10
sleep 3
done
Server address: 10.244.1.171:80
Server name: nginxhello-85f8846c44-kb44r
Date: 21/Dec/2025:03:21:32 +0000
URI: /
Request ID: d9084c441c6ba9bb0da5b085510513fa
Server address: 10.244.0.56:80
Server name: nginxhello-85f8846c44-pzpzs
Date: 21/Dec/2025:03:21:35 +0000
URI: /
Request ID: a9308c0ba063904633db02e240be6cdc
Server address: 10.244.0.190:80
Server name: nginxhello-85f8846c44-v88f8
Date: 21/Dec/2025:03:21:39 +0000
URI: /
Request ID: daef9ca7d98cae79dd762b5c2805f129
Server address: 10.244.1.171:80
Server name: nginxhello-85f8846c44-kb44r
Date: 21/Dec/2025:03:21:43 +0000
URI: /
Request ID: 63da67ee67c344ef7a6f518f2e89c5cd
Server address: 10.244.1.247:80
Server name: nginxhello-85f8846c44-vtgtz
Date: 21/Dec/2025:03:21:46 +0000
URI: /
Request ID: 9bbc5a0b27b70faedbc1cefef86fe8a5
Server address: 10.244.0.190:80
Server name: nginxhello-85f8846c44-v88f8
Date: 21/Dec/2025:03:21:50 +0000
URI: /
Request ID: ef39a32f3439029ead44a65e1f89c910
Server address: 10.244.0.56:80
Server name: nginxhello-85f8846c44-pzpzs
Date: 21/Dec/2025:03:21:54 +0000
URI: /
Request ID: ebce81d196d8ff7928cceba90cfc2695
Server address: 10.244.1.247:80
Server name: nginxhello-85f8846c44-vtgtz
Date: 21/Dec/2025:03:21:57 +0000
URI: /
Request ID: 1df619bc2b59dffd722f6427c5856ff1
Server address: 10.244.1.247:80
Server name: nginxhello-85f8846c44-vtgtz
Date: 21/Dec/2025:03:22:01 +0000
URI: /
Request ID: 86c0c4cb734fab92f7e6b33b9fc1b1b3
Server address: 10.244.0.190:80
Server name: nginxhello-85f8846c44-v88f8
Date: 21/Dec/2025:03:22:04 +0000
URI: /
Request ID: 9426a571bdc919f2ee300a2d960b9f9d
Server address: 10.244.1.171:80
Server name: nginxhello-85f8846c44-kb44r
Date: 21/Dec/2025:03:22:08 +0000
URI: /
Request ID: 4a02a251a6da83c35b0b973d7a146f9e
Server address: 10.244.1.247:80
Server name: nginxhello-85f8846c44-vtgtz
Date: 21/Dec/2025:03:22:12 +0000
URI: /
Request ID: a5d2ee01c3e63c190d9ece943fab8c9b
Server address: 10.244.1.247:80
Server name: nginxhello-85f8846c44-vtgtz
Date: 21/Dec/2025:03:22:15 +0000
URI: /
Request ID: 034719e79ca8d99812d0fc8cfe423ac3
Server address: 10.244.1.247:80
Server name: nginxhello-85f8846c44-vtgtz
Date: 21/Dec/2025:03:22:19 +0000
URI: /
Request ID: d3c0ff1623c129173ccfc216c128af2c
Server address: 10.244.1.247:80
Server name: nginxhello-85f8846c44-vtgtz
Date: 21/Dec/2025:03:22:22 +0000
URI: /
Request ID: 2768562909358b7fb2cafa13ba584846
Server address: 10.244.0.56:80
Server name: nginxhello-85f8846c44-pzpzs
Date: 21/Dec/2025:03:22:26 +0000
URI: /
Request ID: be52f52629303217ea92a9633d9ccee3
Server address: 10.244.1.171:80
Server name: nginxhello-85f8846c44-kb44r
Date: 21/Dec/2025:03:22:30 +0000
URI: /
Request ID: 34a649f112ba6467116d8b1fa26635e7
Server address: 10.244.1.171:80
Server name: nginxhello-85f8846c44-kb44r
Date: 21/Dec/2025:03:22:34 +0000
URI: /
Request ID: ced52413e432d5a5dd9efc0da06496e6
Server address: 10.244.0.190:80
Server name: nginxhello-85f8846c44-v88f8
Date: 21/Dec/2025:03:22:38 +0000
URI: /
Request ID: d39b782b497671fbbf71bc28bca4b050
Server address: 10.244.1.247:80
Server name: nginxhello-85f8846c44-vtgtz
Date: 21/Dec/2025:03:22:42 +0000
URI: /
Request ID: 3be25b71dbafd92e261f42632e53e213
```



