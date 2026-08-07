# Validation Evidence

Lab 01 was validated against the deployed AWS environment using `validate.sh`.

## Result

- PASS: VPC CIDR is correct
- PASS: Lab VPC is not the default VPC
- PASS: DNS support is enabled
- PASS: DNS hostnames are enabled
- PASS: Public subnet AZ1 uses `10.10.1.0/24`
- PASS: Public subnet AZ1 public IPv4 setting is enabled
- PASS: Public subnet AZ2 uses `10.10.2.0/24`
- PASS: Public subnet AZ2 public IPv4 setting is enabled
- PASS: Private subnet AZ1 uses `10.10.11.0/24`
- PASS: Private subnet AZ1 public IPv4 setting is disabled
- PASS: Private subnet AZ2 uses `10.10.12.0/24`
- PASS: Private subnet AZ2 public IPv4 setting is disabled
- PASS: Internet gateway is attached
- PASS: Public default route targets the internet gateway
- PASS: Private route table has no internet default route
- PASS: Public route table is associated with two subnets
- PASS: Private route table is associated with two subnets

**All VPC foundation checks passed.**

Account IDs and AWS resource IDs are intentionally excluded from this public evidence.
