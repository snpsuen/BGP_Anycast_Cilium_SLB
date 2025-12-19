![BGP_anycast_cilium](bgp_anycast_cilium.png)

In this exercise, we are going to build and experiment with BGP anyscast routes that steer client requests to a service VIP advertised by the Cilium CNI provider from two Kubernetes clusters. The work will be carried out in a nifty but realistic emulation lab where all the assets including the FRR switch container and Kind K8s clusters are deployed by hand.

### Why does it matter?

As Cilium is becomming the CNI of choice for Kubernetes, we hope to create a golden template for users to conigure 
