![BGP_anycast_cilium](bgp_anycast_cilium.png)

In this exercise, we will build and experiment with BGP anyscast routes that steer client requests to a service VIP advertised by the Cilium CNI provider from two Kubernetes clusters. The work will be carried out in a nifty but realistic emulation lab where all the assets including the FRR switch container and Kind K8s clusters are deployed by hand.

### Why does it matter?

As Cilium is becoming the CNI of choice for Kubernetes, we hope to create a golden template for users to configure the Cilium BGP control plane in a standard way for Kubernetes service load balancing. It also caters for the configuration of an FRR router as a typical upstream BGP neigbour to interact with Cilium on two or more Kubernetes clusters. 

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

### 1. Deploy the Kind Kubernetes clusters

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

Perform post-deployment routines on the Kind cluster nodes by adding return routes for the client network and installing auxilliary utilities.
```
docker exec kind01-control-plane ip route add 192.168.20.0/24 via 10.20.0.101 dev eth0
docker exec kind01-worker ip route add 192.168.20.0/24 via 10.20.0.101 dev eth0

docker exec kind01-control-plane bash -c "apt-get update && apt-get install iputils-ping"
docker exec kind01-worker bash -c "apt-get update && apt-get install iputils-ping"
```

```
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl config current-context
kind-kind01
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl get nodes -o wide
NAME                   STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION       CONTAINER-RUNTIME
kind01-control-plane   Ready    control-plane   8m17s   v1.34.0   10.20.0.3     <none>        Debian GNU/Linux 12 (bookworm)   5.15.0-156-generic   containerd://2.1.3
kind01-worker          Ready    <none>          7m51s   v1.34.0   10.20.0.2     <none>        Debian GNU/Linux 12 (bookworm)   5.15.0-156-generic   containerd://2.1.3
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$
```

Similarly use kind to create the second Kubernetes cluster called kind02 on the the user defined subnet 172.20.0.0/16
```
docker network create --subnet=172.20.0.0/16 kind02
export KIND_EXPERIMENTAL_DOCKER_NETWORK=kind01
kind create cluster --config=- <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: kind02
nodes:
 - role: control-plane
 - role: worker
EOF

docker exec kind02-control-plane ip route add 192.168.20.0/24 via 172.20.0.101 dev eth0
docker exec kind02-worker ip route add 192.168.20.0/24 via 172.20.0.101 dev eth0
docker exec kind02-control-plane bash -c "apt-get update && apt-get install iputils-ping"
docker exec kind02-worker bash -c "apt-get update && apt-get install iputils-ping"
```

```
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl config current-context
kind-kind02
keyuser@ubunclone:~/BGP_Anycast_Cilium_SLB$ kubectl get nodes -o wide
NAME                   STATUS   ROLES           AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION       CONTAINER-RUNTIME
kind02-control-plane   Ready    control-plane   2m32s   v1.34.0   172.20.0.2    <none>        Debian GNU/Linux 12 (bookworm)   5.15.0-156-generic   containerd://2.1.3
kind02-worker          Ready    <none>          2m12s   v1.34.0   172.20.0.3    <none>        Debian GNU/Linux 12 (bookworm)   5.15.0-156-generic   containerd://2.1.3
```

### Install Cilum in Kubernetes

Before installation, it is necessary to remove the default CNI that comes with Kind together with the kube-proxy and kindnet daemon sets.
```
kubectl delete daemonset -n kube-system kube-proxy
kubectl delete daemonset -n kube-system kindnet
docker exec kind01-control-plane rm -rf /etc/cni/net.d/*
docker exec kind01-worker rm -rf /etc/cni/net.d/*
```











