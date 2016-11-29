# Prerequisite
Install AWS CLI and jq

See **0_prerequisite.sh** for details

# AWS Pre Warm
Edit **1_pre_warm_aws.sh**

Update next lines
```
AWS_ACCESS_KEY_ID="REPLACE_WITH_YOUR_ACCESS_KEY_ID"
AWS_SECRET_ACCESS_KEY="REPLACE_WITH_YOUR_SECRET_ACCESS_KEY"
```
and don't forget to change S3 bucket name
```
CF_S3_BUCKET_NAME="cf-templates-ecs-demo"
```

run:
```
bash 1_pre_warm_aws.sh
```

# Prepare ENV variables
Replace AWS access keys, Region, EIPs, S3 bucket name variables(and others if any) with those you have created during Pre Warm step (look into cformation- files)

Run the below commands:
```
export AWS_ACCESS_KEY_ID="CLOUDFORMATION_AWS_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="CLOUDFORMATION_AWS_SECRET_KEY"
export AWS_DEFAULT_REGION="eu-west-1"
export cf_param_cf_ec2_key_pare="automation-ssh-key"
export cf_param_deploy_environment="dev"
export cf_param_cloud_formation_stack_version="1"
export cf_param_backend_one_service_version="latest"
export cf_param_frontend_service_version="latest"
export cf_param_cf_templates_s3_bucket_name="cf-templates-ecs-demo-bucket"
export cf_param_nat_gateway_a_allocation_id="eipalloc-e07d5084"
export cf_param_nat_gateway_b_allocation_id="eipalloc-6c614c08"
export cf_param_nat_gateway_c_allocation_id="eipalloc-dd624fb9"
export cf_param_with_nat_gateways_stack="yes"
export cf_param_with_ecs_external_stack="yes"
export cf_param_with_ecs_internal_stack="yes"
export cf_param_public_hosted_zone="ZAAFS5LV4SXNY"
export cf_param_domain_name="mydemo.click"
```

If you don't have a public domain in Route53, you need to disable PublicRecordSet creation by setting:
```
export cf_param_public_hosted_zone="VOID"
export cf_param_domain_name="VOID"
```

If you don't want to create NAT Gateways(Internal ECS Cluster won't work without them, so disable it also) then set:
```
export cf_param_with_nat_gateways_stack="no"
export cf_param_with_ecs_internal_stack="no"
```


# Create CloudFormation stack

> NOTE: If your bucket is in the US-East-1 (N. Virginia) region, you must use the http://s3.amazonaws.com/bucket endpoint. This means that you have update all the scripts and CloudFormation templates and remove AWS::Region or $aws_region variable from s3 paths.

Run (in the same command line you used for the "export" step ):
```
bash 2_create_or_update_cf_stack.sh
```

You watch the progress in your CLI or you can go to AWS Console > CloudFormation and watch events there.

*Full stack creation will take about 15-20 minutes*

# Verify

* If you used own domain, then go to http://frontend.your_domain.com and http://frontend.your_domain.com/backend-api
* If don't, go to AWS Console > EC2 > LoadBalancers. Find ELB with *public* in its name and copy its DNS name. Go to https://elb-domain-name-you-just.copi.ed
* In both cases you should see "This is Fronted Service running by AWS ECS"

# Clean Up

Go to AWS Console > CloudFormation.
Select main stack and delete it

Once CloudFormation stack is deleted. Go to AWS Console > EC2 > Elastic IPs.
Select all IPs and remove them

Go to AWS Console > S3.
Select you bucket with CFormation templates and remove it

# Costs
Running the full stack (3 NAT Gateways, 3 EIPs, 2 ELBs, 4 t2.nano instances, 1 private hosted zone) will cost you 1$/hour approx. 

> NOTE: Amazon charges you hourly. For example, if the stack was up fo 1 hour and 5 minutes - AWS will charge you for full two hours. 
