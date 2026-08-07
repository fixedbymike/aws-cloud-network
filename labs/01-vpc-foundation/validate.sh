#!/usr/bin/env bash
set -Eeuo pipefail

REGION="${AWS_REGION:-us-east-1}"
VPC_NAME="cloud-network-lab-vpc"

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] \
    && pass "$message" \
    || fail "$message (expected '$expected', got '$actual')"
}

get_single_id() {
  local value="$1"
  local label="$2"

  [[ -n "$value" && "$value" != "None" ]] || fail "$label was not found."
  [[ "$value" != *$'\t'* && "$value" != *" "* ]] || fail "Multiple $label resources were found."
  printf '%s' "$value"
}

VPC_ID="$(get_single_id \
  "$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=$VPC_NAME" "Name=state,Values=available" \
    --query 'Vpcs[].VpcId' \
    --output text)" \
  "VPC")"

VPC_CIDR="$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --vpc-ids "$VPC_ID" \
  --query 'Vpcs[0].CidrBlock' \
  --output text)"

IS_DEFAULT="$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --vpc-ids "$VPC_ID" \
  --query 'Vpcs[0].IsDefault' \
  --output text)"

DNS_SUPPORT="$(aws ec2 describe-vpc-attribute \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --attribute enableDnsSupport \
  --query 'EnableDnsSupport.Value' \
  --output text)"

DNS_HOSTNAMES="$(aws ec2 describe-vpc-attribute \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --attribute enableDnsHostnames \
  --query 'EnableDnsHostnames.Value' \
  --output text)"

assert_eq "$VPC_CIDR" "10.10.0.0/16" "VPC CIDR is correct"
assert_eq "$IS_DEFAULT" "False" "Lab VPC is not the default VPC"
assert_eq "$DNS_SUPPORT" "True" "DNS support is enabled"
assert_eq "$DNS_HOSTNAMES" "True" "DNS hostnames are enabled"

validate_subnet() {
  local name="$1"
  local expected_cidr="$2"
  local expected_public_ip="$3"

  local subnet_id
  local cidr
  local public_ip

  subnet_id="$(get_single_id \
    "$(aws ec2 describe-subnets \
      --region "$REGION" \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$name" \
      --query 'Subnets[].SubnetId' \
      --output text)" \
    "subnet '$name'")"

  cidr="$(aws ec2 describe-subnets \
    --region "$REGION" \
    --subnet-ids "$subnet_id" \
    --query 'Subnets[0].CidrBlock' \
    --output text)"

  public_ip="$(aws ec2 describe-subnets \
    --region "$REGION" \
    --subnet-ids "$subnet_id" \
    --query 'Subnets[0].MapPublicIpOnLaunch' \
    --output text)"

  assert_eq "$cidr" "$expected_cidr" "$name uses $expected_cidr"
  assert_eq "$public_ip" "$expected_public_ip" "$name public IPv4 setting is $expected_public_ip"
}

validate_subnet public-subnet-az1 10.10.1.0/24 True
validate_subnet public-subnet-az2 10.10.2.0/24 True
validate_subnet private-subnet-az1 10.10.11.0/24 False
validate_subnet private-subnet-az2 10.10.12.0/24 False

IGW_ID="$(get_single_id \
  "$(aws ec2 describe-internet-gateways \
    --region "$REGION" \
    --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'InternetGateways[].InternetGatewayId' \
    --output text)" \
  "attached internet gateway")"

[[ "$IGW_ID" == igw-* ]] \
  && pass "Internet gateway is attached" \
  || fail "Attached internet gateway is invalid"

PUBLIC_RT="$(get_single_id \
  "$(aws ec2 describe-route-tables \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=public-route-table" \
    --query 'RouteTables[].RouteTableId' \
    --output text)" \
  "public route table")"

PRIVATE_RT="$(get_single_id \
  "$(aws ec2 describe-route-tables \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=private-route-table" \
    --query 'RouteTables[].RouteTableId' \
    --output text)" \
  "private route table")"

PUBLIC_DEFAULT_TARGET="$(aws ec2 describe-route-tables \
  --region "$REGION" \
  --route-table-ids "$PUBLIC_RT" \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId | [0]' \
  --output text)"

PRIVATE_DEFAULT_TARGET="$(aws ec2 describe-route-tables \
  --region "$REGION" \
  --route-table-ids "$PRIVATE_RT" \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`] | [0]' \
  --output text)"

PUBLIC_ASSOCIATIONS="$(aws ec2 describe-route-tables \
  --region "$REGION" \
  --route-table-ids "$PUBLIC_RT" \
  --query 'length(RouteTables[0].Associations[?Main==`false`])' \
  --output text)"

PRIVATE_ASSOCIATIONS="$(aws ec2 describe-route-tables \
  --region "$REGION" \
  --route-table-ids "$PRIVATE_RT" \
  --query 'length(RouteTables[0].Associations[?Main==`false`])' \
  --output text)"

assert_eq "$PUBLIC_DEFAULT_TARGET" "$IGW_ID" "Public default route targets the attached internet gateway"
assert_eq "$PRIVATE_DEFAULT_TARGET" "None" "Private route table has no internet default route"
assert_eq "$PUBLIC_ASSOCIATIONS" "2" "Public route table is associated with two subnets"
assert_eq "$PRIVATE_ASSOCIATIONS" "2" "Private route table is associated with two subnets"

echo
echo "All VPC foundation checks passed."
echo
aws ec2 describe-subnets \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].{Name:Tags[?Key==`Name`]|[0].Value,AZ:AvailabilityZone,CIDR:CidrBlock,PublicIPv4:MapPublicIpOnLaunch}' \
  --output table
