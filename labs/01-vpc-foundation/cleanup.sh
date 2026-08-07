#!/usr/bin/env bash
set -Eeuo pipefail

REGION="${AWS_REGION:-us-east-1}"
PROJECT_TAG="CloudNetworkLabs"
VPC_NAME="cloud-network-lab-vpc"

if [[ "${1:-}" != "--destroy" ]]; then
  echo "Refusing to delete resources."
  echo "Run: ./cleanup.sh --destroy"
  exit 1
fi

VPC_ID="$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=$VPC_NAME" "Name=state,Values=available" \
  --query 'Vpcs[].VpcId' \
  --output text)"

if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "No VPC named '$VPC_NAME' was found. Nothing to delete."
  exit 0
fi

if [[ "$VPC_ID" == *$'\t'* || "$VPC_ID" == *" "* ]]; then
  echo "ERROR: Multiple VPCs named '$VPC_NAME' were found. Cleanup stopped." >&2
  exit 1
fi

IS_DEFAULT="$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --vpc-ids "$VPC_ID" \
  --query 'Vpcs[0].IsDefault' \
  --output text)"

TAG_VALUE="$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --vpc-ids "$VPC_ID" \
  --query 'Vpcs[0].Tags[?Key==`Project`].Value | [0]' \
  --output text)"

[[ "$IS_DEFAULT" == "False" ]] || {
  echo "ERROR: Cleanup will never delete a default VPC." >&2
  exit 1
}

[[ "$TAG_VALUE" == "$PROJECT_TAG" ]] || {
  echo "ERROR: Project tag mismatch. Cleanup stopped." >&2
  exit 1
}

ENI_COUNT="$(aws ec2 describe-network-interfaces \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'length(NetworkInterfaces)' \
  --output text)"

if [[ "$ENI_COUNT" != "0" ]]; then
  echo "ERROR: $ENI_COUNT network interface(s) still exist in the VPC." >&2
  echo "Remove dependent workloads before running cleanup." >&2
  aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'NetworkInterfaces[].{Id:NetworkInterfaceId,Status:Status,Description:Description}' \
    --output table
  exit 1
fi

echo "Deleting non-main route tables..."
mapfile -t ROUTE_TABLES < <(
  aws ec2 describe-route-tables \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[].RouteTableId' \
    --output text | tr '\t' '\n'
)

for route_table_id in "${ROUTE_TABLES[@]}"; do
  [[ -n "$route_table_id" ]] || continue

  is_main="$(aws ec2 describe-route-tables \
    --region "$REGION" \
    --route-table-ids "$route_table_id" \
    --query 'length(RouteTables[0].Associations[?Main==`true`])' \
    --output text)"

  if [[ "$is_main" == "0" ]]; then
    mapfile -t ASSOCIATIONS < <(
      aws ec2 describe-route-tables \
        --region "$REGION" \
        --route-table-ids "$route_table_id" \
        --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' \
        --output text | tr '\t' '\n'
    )

    for association_id in "${ASSOCIATIONS[@]}"; do
      [[ -n "$association_id" && "$association_id" != "None" ]] || continue
      aws ec2 disassociate-route-table \
        --region "$REGION" \
        --association-id "$association_id"
    done

    aws ec2 delete-route-table \
      --region "$REGION" \
      --route-table-id "$route_table_id"
  fi
done

echo "Deleting subnets..."
mapfile -t SUBNETS < <(
  aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[].SubnetId' \
    --output text | tr '\t' '\n'
)

for subnet_id in "${SUBNETS[@]}"; do
  [[ -n "$subnet_id" ]] || continue
  aws ec2 delete-subnet --region "$REGION" --subnet-id "$subnet_id"
done

echo "Detaching and deleting internet gateways..."
mapfile -t IGWS < <(
  aws ec2 describe-internet-gateways \
    --region "$REGION" \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[].InternetGatewayId' \
    --output text | tr '\t' '\n'
)

for igw_id in "${IGWS[@]}"; do
  [[ -n "$igw_id" ]] || continue
  aws ec2 detach-internet-gateway \
    --region "$REGION" \
    --internet-gateway-id "$igw_id" \
    --vpc-id "$VPC_ID"

  aws ec2 delete-internet-gateway \
    --region "$REGION" \
    --internet-gateway-id "$igw_id"
done

echo "Deleting VPC..."
aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC_ID"

rm -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state.env"

echo "Cleanup complete."
