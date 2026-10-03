#!/bin/bash
# Tears down the Pockterm App Review demo SSH host. Run AFTER the app is approved.
# Written by scripts/provision-demo-host.sh on 2026-10-03.
#
# NEVER put AWS credentials in this file. It authenticates from the ambient AWS
# CLI config (~/.aws/credentials, outside the repo) — no keys, no --profile, no
# exported AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY. This repository is PUBLIC.
# scripts/routine-update checks this file explicitly and fails if that changes.
set -e
export AWS_PAGER=""
REGION=us-east-1
aws ec2 terminate-instances --region $REGION --instance-ids i-05b5cbc6f716f0014
aws ec2 wait instance-terminated --region $REGION --instance-ids i-05b5cbc6f716f0014
aws ec2 release-address --region $REGION --allocation-id eipalloc-06e0ae65e475358d4
aws ec2 delete-security-group --region $REGION --group-id sg-07a37b0586825a37e 2>/dev/null || true
echo "demo host torn down."
