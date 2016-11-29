#!/bin/bash
# Script that pre-warms AWS account services required for CloudFormation

AUTOMATION_USER="cloudformation-service-user"
AWS_ACCESS_KEY_ID="REPLACE_WITH_YOUR_ACCESS_KEY_ID"
AWS_SECRET_ACCESS_KEY="REPLACE_WITH_YOUR_SECRET_ACCESS_KEY"
CF_EC2_KEY_PARE="automation-ssh-key"
AWS_REGION="eu-west-1"
# S3 bucket name must be uniq. CHANGE IT before running the script
CF_S3_BUCKET_NAME="cf-templates-ecs-demo"

export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$AWS_REGION"

# Add automation user to be used by CF scripts.
echo "Creating automation user, group and policy"
aws iam create-group --group-name AWS_Automation
aws iam create-user --user-name "$AUTOMATION_USER"
aws iam add-user-to-group --user-name "$AUTOMATION_USER" --group-name AWS_Automation
aws iam create-access-key --user-name "$AUTOMATION_USER" > cformation-access-keys.json

cat <<EOF > automation-role.json
{
	"Version": "2012-10-17",
	"Statement": [
	    {
		    "Effect": "Allow",
		    "Action": "*",
		    "Resource": "*"
		}
	]
}
EOF
aws iam put-group-policy --group-name AWS_Automation --policy-document file://automation-role.json --policy-name AdministratorAccess
echo "Done"

# S3 bucket for CFormation templates
echo "Creating S3 bucket"
aws s3api create-bucket --bucket "$CF_S3_BUCKET_NAME" --region "$AWS_REGION"
echo "IF you are getting errors during this step just try to change the bucket name. Or create the bucket manually through AWS Console"

# EC2 related:
echo "Creating EC2 keypair and allocationg EIP"
aws ec2 create-key-pair --key-name "$CF_EC2_KEY_PARE" --output text > cformation-ssh-key.json

aws ec2 allocate-address --domain vpc > cformation-eips.json
aws ec2 allocate-address --domain vpc >> cformation-eips.json
aws ec2 allocate-address --domain vpc >> cformation-eips.json
echo "Done"

echo "ALL DONE. Check all files with cformation-* prefix created in the script workdir"
