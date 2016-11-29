#!/bin/bash
set -e

RED='\033[00;31m'
GREEN='\033[00;32m'
BLUE='\033[00;34m'
RESTORE='\033[0m'

bad_initial_stack_statuses=("CREATE_FAILED" "DELETE_FAILED" "DELETE_IN_PROGRESS" "ROLLBACK_FAILED" "UPDATE_ROLLBACK_FAILED")
busy_initial_stack_statuses=("ROLLBACK_IN_PROGRESS" "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS" "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS" "UPDATE_ROLLBACK_IN_PROGRESS")
good_initial_stack_statuses=("CREATE_COMPLETE" "ROLLBACK_COMPLETE" "UPDATE_COMPLETE" "UPDATE_ROLLBACK_COMPLETE")

cidr_prefix="10.120"
sleep_seconds=15
aws_region="$AWS_DEFAULT_REGION"
environment_name="$cf_param_deploy_environment"
cloud_formation_stack_version="$cf_param_cloud_formation_stack_version"
cf_s3_bucket_name="$cf_param_cf_templates_s3_bucket_name"
key_name="$cf_param_cf_ec2_key_pare"
public_hosted_zone="$cf_param_public_hosted_zone"
domain_name="$cf_param_domain_name"
with_nat_gateways_stack="$cf_param_with_nat_gateways_stack"
with_ecs_external_stack="$cf_param_with_ecs_external_stack"
with_ecs_internal_stack="$cf_param_with_ecs_internal_stack"
backend_one_service_version="$cf_param_backend_one_service_version"
frontend_service_version="$cf_param_frontend_service_version"
nat_gateway_a_allocation_id="$cf_param_nat_gateway_a_allocation_id"
nat_gateway_b_allocation_id="$cf_param_nat_gateway_b_allocation_id"
nat_gateway_c_allocation_id="$cf_param_nat_gateway_c_allocation_id"


script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

logger() {
    local color="$BLUE"
    case "$2" in
        "ERR" )
            color="$RED" ;;
        "SUC" )
            color="$GREEN" ;;
    esac
    echo -e "$color### $1$RESTORE"
}

cf_list() {
    aws cloudformation list-stacks \
        --stack-status  \
        CREATE_COMPLETE \
        CREATE_FAILED \
        CREATE_IN_PROGRESS \
        DELETE_FAILED \
        DELETE_IN_PROGRESS \
        ROLLBACK_COMPLETE \
        ROLLBACK_FAILED \
        ROLLBACK_IN_PROGRESS \
        UPDATE_COMPLETE \
        UPDATE_COMPLETE_CLEANUP_IN_PROGRESS \
        UPDATE_IN_PROGRESS \
        UPDATE_ROLLBACK_COMPLETE \
        UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS \
        UPDATE_ROLLBACK_FAILED \
        UPDATE_ROLLBACK_IN_PROGRESS \
        --query "StackSummaries[].StackName" \
        --output text | tr '\t' '\n' | sort | grep "$1" || exit_code=$?
        if (( exit_code > 1 )) ; then
            exit $exit_code
        fi
}

get_user_data() {
    local stack_name="$1"
    local network_type="$2"
    local instance_type="$3"
    local out_file="$3_userdata.json"
    local err_file="$3_userdata.err"
    instance_id=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$stack_name-$network_type-$instance_type" --max-items 1 --query 'Reservations[0].Instances[0].InstanceId' --output text | grep i-)
    $(2> "$err_file" 1> "$out_file" aws ec2 describe-instance-attribute --instance-id "$instance-id" --attribute userData)
}

get_instance_description() {
    local stack_name="$1"
    local network_type="$2"
    local instance_type="$3"
    local out_file="$3_description.json"
    local err_file="$3_description.err"
    instance_id=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$stack_name-$network_type-$instance_type" --max-items 1 --query 'Reservations[0].Instances[0].InstanceId' --output text | grep i-)
    $(2> "$err_file" 1> "$out_file" aws ec2 describe-instances --instance-id "$instance-id")
}

prop_length() {
    local file="$1"
    local property="$2"
    echo $(cat "$file" | jq -r "$property | length")
}

prop_from_json() {
    local file="$1"
    local property="$2"
    echo $(cat "$file" | jq -r "$property")
}

stack_info() {
    local stack_name="$1"
    local out_file="stack.json"
    local err_file="stack.err"
    $(2> "$err_file" 1> "$out_file" aws cloudformation describe-stacks --stack-name "$stack_name")
}

stack_events() {
    local stack_name="$1"
    local out_file="stack_events.json"
    local err_file="stack_events.err"
    $(2> "$err_file" 1> "$out_file" aws cloudformation describe-stack-events --stack-name "$stack_name" --max-items 50)
}

check_bad_stack_status() {
    local initial_stack_status="$1"

    for bad_initial_stack_status in "${bad_initial_stack_statuses[@]}"; do
        if [ "$initial_stack_status" = "$bad_initial_stack_status" ]; then
            logger "Stack has a bad initial status: $initial_stack_status\nExiting..." "ERR"
            exit 1
        fi
    done
    check_busy_stack_status "$initial_stack_status"
}

check_busy_stack_status() {
    local initial_stack_status="$1"

    for busy_initial_stack_status in "${busy_initial_stack_statuses[@]}"; do
        if [ "$initial_stack_status" = "$busy_initial_stack_status" ]; then
            local busy_timer=0

            while [[ "$initial_stack_status" = "$busy_initial_stack_status" ]] && [[ "$busy_timer" -le 15 ]]; do
                logger "Stack has a busy initial status: $initial_stack_status\nWaiting 60 seconds..."
                sleep 60
                stack_info "$environment_name"
                local initial_stack_status=$(prop_from_json "stack.json" ".Stacks[0].StackStatus")
            done

            if [ "$initial_stack_status" = "$busy_initial_stack_status" ]; then
                logger "The stack seems to stuck with $initial_stack_status\nEXiting" "ERR"
                exit 1
            fi
            logger "The stack has changed its status to: $initial_stack_status\n"
            check_good_stack_status "$initial_stack_status"
        fi
    done
}

check_good_stack_status() {
    local initial_stack_status="$1"

    for good_initial_stack_status in "${good_initial_stack_statuses[@]}"; do
        if [ "$initial_stack_status" = "$good_initial_stack_status" ]; then
            return 1
        fi
    done
    check_bad_stack_status "$initial_stack_status"

}

watch_cloudformation_events() {

    stack_info "$environment_name"
    local initial_stack_status=$(prop_from_json "stack.json" ".Stacks[0].StackStatus")
    logger "Initial stack status: $initial_stack_status"

    check_bad_stack_status "$initial_stack_status"

    current_stack_status="$initial_stack_status"

    local event_ids=""
    while true; do

        logger "Sleep for: $sleep_seconds seconds"
        sleep "$sleep_seconds"

        stack_events "$environment_name"
        event_count=$(prop_length "stack_events.json" ".StackEvents")

        for (( index=$event_count-1; index >= 0; index-- )); do
            current_event_id=$(prop_from_json "stack_events.json" ".StackEvents[$index].EventId")
            if [[ "$event_ids" != *"'$current_event_id'"* ]];
            then
                event_ids="$event_ids '$current_event_id'"
                timestamp=$(prop_from_json "stack_events.json" ".StackEvents[$index].Timestamp")
                resource_type=$(prop_from_json "stack_events.json" ".StackEvents[$index].ResourceType")
                resource_status=$(prop_from_json "stack_events.json" ".StackEvents[$index].ResourceStatus")
                resource_status_reason=$(prop_from_json "stack_events.json" ".StackEvents[$index].ResourceStatusReason")
                logical_resource_id=$(prop_from_json "stack_events.json" ".StackEvents[$index].LogicalResourceId")
                logger "Event: $timestamp, $current_event_id, $resource_type, $logical_resource_id, $resource_status, $resource_status_reason"
            fi
        done

        stack_info "$environment_name"
        current_stack_status=$(prop_from_json "stack.json" ".Stacks[0].StackStatus")

        if [[ "$initial_stack_status" != "$current_stack_status" ]];
        then
            if [ \( "$current_stack_status" = "ROLLBACK_IN_PROGRESS" \) -o \( "$current_stack_status" = "UPDATE_ROLLBACK_IN_PROGRESS" \) -o \( "$current_stack_status" = "CREATE_FAILED" \) ]; then
                logger "Stack creation/update has failed with status: $current_stack_status" "ERR"
                exit 1
            fi
            break
        fi

    done
}


cf_create() {
    local stack="$1"
    local template="$2"
    local params="$3"
    if aws cloudformation create-stack --disable-rollback --stack-name $stack --template-url $template --parameters "file://$params" --capabilities CAPABILITY_IAM || exit $?
    then
        watch_cloudformation_events "$stack"
    fi
}

cf_update() {
    local stack="$1"
    local template="$2"
    local params="$3"
    if aws cloudformation update-stack --stack-name $stack --template-url $template --parameters "file://$params" --capabilities CAPABILITY_IAM || exit $?
    then
        watch_cloudformation_events "$stack"
    fi
}

cf_delete() {
    local stack="$1"
    if aws cloudformation delete-stack --stack-name $stack
    then
        watch_cloudformation_events "$stack"
    fi
}

cf_delete_and_create() {
    local stack="$1"
    local template="$2"
    local params="$3"
    echo "Deleting $stack"
    cf_delete "$stack"
    echo "Creating stack: $stack"
    cf_create "$stack" "$template" "$params"
}

cf_create_or_update() {

    # Create CloudFormation template parameters JSON file.
cat <<EOF > ./cloud-formation-parameters.json
[
    {
        "ParameterKey": "EnvironmentName",
        "ParameterValue": "$environment_name",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "CidrPrefix",
        "ParameterValue": "$cidr_prefix",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "KeyName",
        "ParameterValue": "$key_name",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "CloudFormationTemplatesS3Bucket",
        "ParameterValue": "$cf_s3_bucket_name",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "CloudFormationVersion",
        "ParameterValue": "$cloud_formation_stack_version",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "BackendOneServiceVersion",
        "ParameterValue": "$backend_one_service_version",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "FrontedServiceVersion",
        "ParameterValue": "$frontend_service_version",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "PublicHostedZone",
        "ParameterValue": "$public_hosted_zone",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "DomainName",
        "ParameterValue": "$domain_name",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "WithNatGatewaysStack",
        "ParameterValue": "$with_nat_gateways_stack",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "WithEcsExternalStack",
        "ParameterValue": "$with_ecs_external_stack",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "WithEcsInternalStack",
        "ParameterValue": "$with_ecs_internal_stack",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "NatGatewayEipAllocationIdSubnetA",
        "ParameterValue": "$nat_gateway_a_allocation_id",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "NatGatewayEipAllocationIdSubnetB",
        "ParameterValue": "$nat_gateway_b_allocation_id",
        "UsePreviousValue": false
    },
    {
        "ParameterKey": "NatGatewayEipAllocationIdSubnetC",
        "ParameterValue": "$nat_gateway_c_allocation_id",
        "UsePreviousValue": false
    }
]
EOF

    # Sync CloudFormation templates to S3.
    aws s3 sync "$script_dir/../templates" "s3://$cf_s3_bucket_name/versions/$cloud_formation_stack_version"

    # Create or update CloudFormation stack.
    stack_list="$(cf_list $environment_name)"
    if [ -z "$stack_list" ] ; then
        logger "Creating stack: $environment_name"
        echo "https://s3-$aws_region.amazonaws.com/$cf_s3_bucket_name/versions/$cloud_formation_stack_version/main.json"
        cf_create "$environment_name" "https://s3-$aws_region.amazonaws.com/$cf_s3_bucket_name/versions/$cloud_formation_stack_version/main.json" "cloud-formation-parameters.json"
        logger "Stack created!" "SUC"
    else
        logger "Updating stack."
        cf_update "$environment_name" "https://s3-$aws_region.amazonaws.com/$cf_s3_bucket_name/versions/$cloud_formation_stack_version/main.json" "cloud-formation-parameters.json"
        logger "Stack updated!" "SUC"
    fi
}

cf_create_or_update
