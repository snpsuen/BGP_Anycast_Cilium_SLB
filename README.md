![BGP_anycast_cilium](bgp_anycast_cilium.png)

In this exercise, we are going to build and experiment with BGP anyscast routes destined to a service VIP that is advertised natively by the Cilium CNI provider from two Kubernetes clusters. The work will be carried out in a nifty but realistic emulation lab where all the sets including the FRR switch container and Kind K8s clusters are deployed by hand.

### Why does it matter?

We hope to 
