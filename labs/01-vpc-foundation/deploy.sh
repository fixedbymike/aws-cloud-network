#!/usr/bin/env bash
set -Eeuo pipefail

REGION="${AWS_REGION:-us-east-1}"
PROJECT_TAG="CloudNetworkLabs"
VPC_NAME="cloud-network-lab-vpc"
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.state.env"

command -v aws >/dev/null 2>&1 || {
  echo "ERROR: AWS CLI is required." >&2
  exit 1
}

echo "Checking AWS identity..."
aws sts get-caller-identity --query Arn --output text >/dev/null

existing_vpcs="$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=$VPC_NAME" "Name=state,Values=available" \
  --query 'Vpcs[].VpcId' \
  --output text)"

if [[ -n "$existing_vpcs" && "$existing_vpcs" != "None" ]]; then
  echo "ERROR: A VPC named '$VPC_NAME' already exists in $REGION."
  echo "Run ./validate.sh to inspect it instead of creating a duplicate."
  exit 1
fi

AZ1="$(aws ec2 describe-availability-zones \
  --region "$REGION" \
  --filters Name=state,Values=available \
  --query 'AvailabilityZones[0].ZoneName' \
  --output text)"

AZ2="$(aws ec2 describe-availability-zones \
  --region "$REGION" \
  --filters Name=state,Values=available \
  --query 'AvailabilityZones[1].ZoneName' \
  --output text)"

echo "Creating VPC..."
VPC_ID="$(aws ec2 create-vpc \
  --region "$REGION" \
  --cidr-block 10.10.0.0/16 \
  --tag-specifications \
  "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME},{Key=Project,Value=$PROJECT_TAG}]" \
  --query 'Vpc.VpcId' \
  --output text)"

aws ec2 wait vpc-available --region "$REGION" --vpc-ids "$VPC_ID"

aws ec2 modify-vpc-attribute \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --enable-dns-support '{"Value":true}'

aws ec2 modify-vpc-attribute \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --enable-dns-hostnames '{"Value":true}'

echo "Creating and attaching internet gateway..."
IGW_ID="$(aws ec2 create-internet-gateway \
  --region "$REGION" \
  --tag-specifications \
  "ResourceType=internet-gateway,Tags=[{Key=Name,Value=cloud-network-lab-igw},{Key=Project,Value=$PROJECT_TAG}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)"

aws ec2 attach-internet-gateway \
  --region "$REGION" \
  --internet-gateway-id "$IGW_ID" \
  --vpc-id "$VPC_ID"

create_subnet() {
  local az="$1"
  local cidr="$2"
  local name="$3"

  aws ec2 create-subnet \
    --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --availability-zone "$az" \
    --cidr-block "$cidr" \
    --tag-specifications \
    "ResourceType=subnet,Tags=[{Key=Name,Value=$name},{Key=Project,Value=$PROJECT_TAG}]" \
    --query 'Subnet.SubnetId' \
    --output text
}

echo "Creating subnets..."
PUBLIC_1="$(create_subnet "$AZ1" 10.10.1.0/24 public-subnet-az1)"
PUBLIC_2="$(create_subnet "$AZ2" 10.10.2.0/24 public-subnet-az2)"
PRIVATE_1="$(create_subnet "$AZ1" 10.10.11.0/24 private-subnet-az1)"
PRIVATE_2="$(create_subnet "$AZ2" 10.10.12.0/24 private-subnet-az2)"

aws ec2 modify-subnet-attribute \
  --region "$REGION" \
  --subnet-id "$PUBLIC_1" \
  --map-public-ip-on-launch

aws ec2 modify-subnet-attribute \
  --region "$REGION" \
  --subnet-id "$PUBLIC_2" \
  --map-public-ip-on-launch

echo "Creating route tables..."
PUBLIC_RT="$(aws ec2 create-route-table \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications \
  "ResourceType=route-table,Tags=[{Key=Name,Value=public-route-table},{Key=Project,Value=$PROJECT_TAG}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)"

PRIVATE_RT="$(aws ec2 create-route-table \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --tag-specifications \
  "ResourceType=route-table,Tags=[{Key=Name,Value=private-route-table},{Key=Project,Value=$PROJECT_TAG}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)"

aws ec2 create-route \
  --region "$REGION" \
  --route-table-id "$PUBLIC_RT" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID" >/dev/null

aws ec2 associate-route-table \
  --region "$REGION" \
  --route-table-id "$PUBLIC_RT" \
  --subnet-id "$PUBLIC_1" >/dev/null

aws ec2 associate-route-table \
  --region "$REGION" \
  --route-table-id "$PUBLIC_RT" \
  --subnet-id "$PUBLIC_2" >/dev/null

aws ec2 associate-route-table \
  --region "$REGION" \
  --route-table-id "$PRIVATE_RT" \
  --subnet-id "$PRIVATE_1" >/dev/null

aws ec2 associate-route-table \
  --region "$REGION" \
  --route-table-id "$PRIVATE_RT" \
  --subnet-id "$PRIVATE_2" >/dev/null

cat > "$STATE_FILE" <<EOF
REGION=$REGION
VPC_ID=$VPC_ID
IGW_ID=$IGW_ID
PUBLIC_1=$PUBLIC_1
PUBLIC_2=$PUBLIC_2
PRIVATE_1=$PRIVATE_1
PRIVATE_2=$PRIVATE_2
PUBLIC_RT=$PUBLIC_RT
PRIVATE_RT=$PRIVATE_RT
EOF

chmod 600 "$STATE_FILE"

echo
echo "Deployment complete."
echo "Local resource state saved to .state.env (ignored by Git)."
echo
aws ec2 describe-subnets \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].{Name:Tags[?Key==`Name`]|[0].Value,AZ:AvailabilityZone,CIDR:CidrBlock,PublicIPv4:MapPublicIpOnLaunch}' \
  --output table
