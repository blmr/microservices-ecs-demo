# About

## Main stack
* Is used to create all other stacks and reuse service templates

## Network stack
* Single VPC with 3 private and 3 public Subnets. Each one is separate AZ.
* Default route for Public subnets is set to a single Internet Gateway (IGW)
* Optionally deploys(enabled by default) nat-gateways sub-stack with 3 NAT Gateways to Public Subnets to provide Private subnets with internet access (required by ECS agents).
* Default route for Private subnets is set to NAT Gateways.
* NAT Gateways are using pre-allocated EIP's
* If NAT Gateways stack is disabled - private subnets will have access only to resources within the VPC
* VPC Endpoint is deployed to the VPC. It provides direct access to S3 buckets (your buckets and Ubuntu mirrors hosted in AWS)

## ECS Service
* There are 2 ECS Clusters. One for Public subnets and hosts Client-facing ECS services. The second one deployed to Private subnets and hosts backend services
* Each cluster deployed across all AZ's.
* Each cluster has 2 ECS instances deployed by default (t2.nano)
* Each cluster has one TaskDefinition and ECS Service.
* Each ECS Service has own ELB. Services deployed to External Cluster has Public ELB(Internet-facing) configured. Service in the Internal Cluster has Private ELB(internal).
* Both ELB's has alias set by Route53.
* Private ELB is using .private hosted zone.
* Public ELB can use your domain (if you have one in Route53) or you can use AWS-issued ELB domain name.
* Security groups configured in a way to allow only ELB traffic from Frontend ECS Service to Backend ECS Service
