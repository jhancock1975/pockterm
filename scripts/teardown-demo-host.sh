#!/bin/bash
# Tears down the Pockterm App Review demo SSH host. Run AFTER the app is approved.
set -e
export AWS_PAGER=""
REGION=us-east-1
aws ec2 terminate-instances --region $REGION --instance-ids i-0456513cf8f2ce99e
aws ec2 wait instance-terminated --region $REGION --instance-ids i-0456513cf8f2ce99e
aws ec2 release-address --region $REGION --allocation-id eipalloc-0514db5ca222d2ad5
aws ec2 delete-security-group --region $REGION --group-id sg-0882c1ba44ee5c41d 2>/dev/null || true
aws ec2 delete-key-pair --region $REGION --key-name pockterm-demo
echo "demo host torn down."
