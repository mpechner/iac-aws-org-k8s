locals {
    node_subnet_names = [ "dev-priv-us-west-2a", "dev-priv-us-west-2b", "dev-priv-us-west-2c"]
    rke_subnet_names = [ "dev-rke-us-west-2a", "dev-rke-us-west-2b", "dev-rke-us-west-2c"  ]
    agent_hostnames = [ "agent_01", "agent_02", "agent_03" ]
    server_hostnames = [ "server_01", "server_02", "server_03" ]
    cluster_name = "dev"
    
    # Array of node subnet CIDR blocks
    node_subnet_cidrs = [for subnet in data.aws_subnet.node_subnet_details : subnet.cidr_block]
    
    # Array of RKE subnet CIDR blocks
    rke_subnet_cidrs = [for subnet in data.aws_subnet.rke_subnet_details : subnet.cidr_block]
}