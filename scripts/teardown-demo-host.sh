#!/bin/bash
# Tears down the Pockterm App Review demo SSH host. Run AFTER the app is approved.
# Resources for the 1.1 review host (provisioned 2026-08-01).
set -e
export AWS_PAGER=""
REGION=us-east-1
aws ec2 terminate-instances --region $REGION --instance-ids i-02facca5b3ad9fa11
aws ec2 wait instance-terminated --region $REGION --instance-ids i-02facca5b3ad9fa11
aws ec2 release-address --region $REGION --allocation-id eipalloc-0fbd3f11cb36e7bbc
aws ec2 delete-security-group --region $REGION --group-id sg-04563c235d6cc9a8f 2>/dev/null || true
aws ec2 delete-key-pair --region $REGION --key-name pockterm-demo
echo "demo host torn down."
