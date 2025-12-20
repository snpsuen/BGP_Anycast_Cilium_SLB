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
			<td aligh="left">IP: 192.168.20.2/24</td>
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
			<td aligh="left">IP: 192.168.20.101/24 <br>
                IP: 10.20.0.101/16 <br>
				IP: 172.20.0.101/16 <br>
				BGP ASN: 65001
			</td>
			<td aligh="left">docker run</td>
		</tr>
        <tr>
			<td aligh="left">Kind01 K8s cluster node 1</td>
			<td aligh="left">Container</td>
			<td aligh="left">IP: 10.20.0.2/16</td>
			<td aligh="left">kind create cluster</td>
		</tr>
		<tr>
			<td aligh="left">Kind01 K8s cluster node 2</td>
			<td aligh="left">Container</td>
			<td aligh="left">IP: 10.20.0.3/16</td>
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
			<td aligh="left">IP: 172.20.0.2/16</td>
			<td aligh="left">kind create cluster</td>
		</tr>
		<tr>
			<td aligh="left">Kind02 K8s cluster node 2</td>
			<td aligh="left">Container</td>
			<td aligh="left">IP: 172.20.0.3/16</td>
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
