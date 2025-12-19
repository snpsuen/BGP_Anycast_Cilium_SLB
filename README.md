![BGP_anycast_cilium](bgp_anycast_cilium.png)

In this exercise, we will build and experiment with BGP anyscast routes that steer client requests to a service VIP advertised by the Cilium CNI provider from two Kubernetes clusters. The work will be carried out in a nifty but realistic emulation lab where all the assets including the FRR switch container and Kind K8s clusters are deployed by hand.

### Why does it matter?

As Cilium is becoming the CNI of choice for Kubernetes, we hope to create a golden template for users to configure the Cilium BGP control plane in a standard way for Kubernetes service load balancing. It also caters for the configuration of an FRR router as a typical upstream BGP neigbour to interact with Cilium on two or more Kubernetes clusters. 

All in all, what we are going to do here is ready to extend to more sophisticated use cases of applying global server load balancing (GSLB) at scale to numerous Kubernetes services or ingress gateways that spring up on cloud or on premises nowadays.

### Lab inventory

The lab consists of the following docker or Kubernetes resources that form the underlying topology. All of them are deployed by hand on an Ubuntu VM host.

<table>
	<thead>
		<tr>
			<th scope="col">Topology Node</th>
			<th scope="col">Network Configuration</th>
			<th scope="col">Creation</th>
		</tr>
	</thead>
	<tbody>
		<tr>
			<td aligh="left">Client workstation</td>
			<td aligh="left">Host IP: 192.168.100.11/24</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
    <tr>
			<td aligh="left">Client02 workstation</td>
			<td aligh="left">Host IP: 192.168.200.22/24</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
		<tr>
			<td aligh="left">FRR Leaf 1</td>
			<td aligh="left">Network Prefix: 192.168.100.0/24 <br>
        Network Prefix: 192.168.200.0/24 <br>
				Network Prefix: 10.0.1.0/24 <br>
				BGP ASN: 65001
			</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
		<tr>
			<td aligh="left">FRR Spine</td>
			<td aligh="left">Network Prefix: 10.0.1.0/24 <br>
				Network Prefix: 10.0.2.0/24 <br>
        Network Prefix: 10.0.3.0/24 <br>
				BGP ASN: 64999
			</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
		<tr>
		    <td aligh="left">FRR Leaf 2</td>
			<td aligh="left">Network Prefix: 10.0.2.0/24 <br>
				Network Prefix: 192.168.49.0/24 <br>
				BGP ASN: 65002
			</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
    <tr>
		    <td aligh="left">FRR Leaf 3</td>
			<td aligh="left">Network Prefix: 10.0.3.0/24 <br>
				Network Prefix: 192.168.99.0/24 <br>
				BGP ASN: 65003
			</td>
			<td aligh="left">Created by ContainerLab</td>
		</tr>
		<tr>
		    <td aligh="left">Minikube docker bridge</td>
			<td aligh="left">Network Prefix (transparent): Network Prefix: 192.168.49.0/24
			</td>
			<td aligh="left">Created in advance by Minikube</td>
		</tr>
    <tr>
		    <td aligh="left">Minikube docker bridge</td>
			<td aligh="left">Network Prefix (transparent): Network Prefix: 192.168.99.0/24
			</td>
			<td aligh="left">Created in advance by Minikube</td>
		</tr>
		<tr>
		    <td aligh="left">Minikube K8s cluster01 single node</td>
			<td aligh="left">Host IP: 192.168.49.2/24
			</td>
			<td aligh="left">Created in advance by Minikube</td>
		</tr>
		<tr>
		    <td aligh="left">Minikube K8s cluster02 single node</td>
			<td aligh="left">Host IP: 192.168.99.2/24
			</td>
			<td aligh="left">Created in advance by Minikube</td>
		</tr>
	</tbody>
</table>
