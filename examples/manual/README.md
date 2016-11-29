# 1. Create ECS Cluster
In AWS Console go to EC2 Container Service, click _Create Cluster_, call it "EcsClusterDemo" and chose "Create an Empty Cluster"

# 2. Add ECS instance to the ECS Cluster

## 1. Create an IAM role for EC2 instance
  1. Go to IAM > Roles > Create role. Name it "EcsInstanceRole"
  2. Select Role Type: "Amazon EC2 Role for EC2 Container Service"
  3. Choose "AmazonEC2ContainerServiceforEC2Role" policy
  4. Review and finish the Role creation

## 2. Create Security Groups for ECS instances and ELBs.
  1. Create SG named "EcsInstanceSecurityGroup". Make sure ports _inbound tcp ports 22 and 8080_ are opened to _Anywhere(0.0.0.0/0)_
  2. Create SG named "EcsServiceElbSecurityGroup". Make sure it has _inbound tcp port 80_ opened to _Anywhere(0.0.0.0/0)_.
  3. Copy "EcsInstanceSecurityGroup" security group ID (e.g. sg-1c3dcc7a) and create new _outbound_ rule for "EcsServiceElbSecurityGroup" with _tcp port 8080_ opened to  _Custom_ destination: _sg-1c3dcc7a_. This will allow the ELB to send its traffic to ECS instances.
  4. Now copy "EcsServiceElbSecurityGroup" security group ID (e.g. sg-853dcce3) and create new _inbound_ rule for "EcsInstanceSecurityGroup" with _tcp port 8080_ opened to _Custom_ destination: _sg-853dcce3_. This will allow incoming traffic to port 8080 comming from the ELB.

## 3. Launch EC2 instance from Amazon ECS-optimized AMI

  1. Find the AMI ID (e.g. ami-175f1964 for eu-west-1) for your region on the page below http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html
  2. In AWS EC2 Console click "Launch Instance", go to Community AMIs tab, paste the AMI ID into Search field and click select.
  3. Go through EC2 Launch Wizard and under "Step 3: Configure Instance Details" > Set _Number of Instances=2_, for _IAM Role_ choose "EcsInstanceRole",
  4. On the same page click _Advanced_ and add the following script into _User Data_:
```
#!/bin/bash
echo "ECS_CLUSTER=EcsClusterDemo" >> /etc/ecs/ecs.config
echo "ECS_LOGFILE=/var/log/ecs.log" >> /etc/ecs/ecs.config
echo "ECS_LOGLEVEL=warn" >> /etc/ecs/ecs.config
```
  5. Don't forget to choose "EcsInstanceSecurityGroup" as a Security Group for the instance
  6. Launch the instance

# 3. Create ECS Task Definition
  1. In EC2 Container Service go to Task Definitions tab and click _Create new Task Definition_
  2. Name it "EcsTaskDefinitionDemo", click _Configure via JSON_ and copy-paste next configuration:
  
  ```
  {
    "containerDefinitions": [
        {
            "name": "NginxContainer",
            "cpu": "512",
            "memory": "256",
            "memoryReservation": "128",
            "essential": "true",
            "image": "nginx:1.10",
            "portMappings": [
                {
                    "hostPort": "8080",
                    "containerPort": "80",
                    "protocol": "tcp"
                }
            ],
            "environment": [
                {
                    "name": "ENVIRONMENT_TYPE",
                    "value": "ECS_DEMO"
                }
            ],
            "mountPoints": [
                {
                    "containerPath": "/var/demo-volume",
                    "sourceVolume": "DemoVolume"
                }
            ],
            "volumesFrom": null,
            "hostname": null,
            "user": null,
            "workingDirectory": null,
            "extraHosts": null,
            "logConfiguration": null,
            "ulimits": null,
            "dockerLabels": null
        }
    ],
    "volumes": [
        {
            "host": {
                "sourcePath": "/tmp"
            },
            "name": "DemoVolume"
        }
    ],
    "networkMode": "bridge",
    "family": "EcsTaskDefinitionDemo"
}
```

# 4. Create ELB for an ECS Service
  1. Go EC2 Console > Load Balancers and Click _Create Load Balancer_ and choose Classic ELB
  2. Name the ELB EcsServiceLoadBalancer
  3. Listener Configuration:

    http:80 -> http:8080
  4. Assign "EcsServiceElbSecurityGroup" to the ELB
  5. Skip Security Configuration
  6. Configure Health Check:

    Ping Protocol: HTTP
    Ping Port: 8080
    Ping Path: /
  7. On the next page choose your ECS instances you have created earlier.

# 5. Create ECS Service
  1. Open "EcsClusterDemo" under EC2 Container Service Console
  2. Click Create under Services tab
  3. Choose

    Task Definition: EcsTaskDefinitionDemo:1
    Service name: NginxContainer
    Number of tasks: 1

  4. Click Configure ELB > Chose Classic ELB

    Select  "EcsServiceLoadBalancer"

    Select IAM role for service "EcsServiceRole"
  5. Click Save > click Create Service

Open _NginxContainer_ service. Check if _Running tasks = 1_.
Now go to load balancer and check if it has 1 instance "inService" under _Instances_ tab. If not, add it manually via "Edit Instances"
Finally, find ELB dns name under Description and open it in browser.
You should see **"Welcome to nginx!"**
