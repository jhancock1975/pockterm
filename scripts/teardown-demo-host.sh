#!/bin/bash
# Tears down the Pockterm App Review demo SSH host. Run AFTER the app is approved.
# Written by scripts/provision-demo-host.sh on 2026-10-13.
#
# NEVER put AWS credentials in this file. It authenticates from the ambient AWS
# CLI config (~/.aws/credentials, outside the repo) — no keys, no --profile, no
# exported AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY. This repository is PUBLIC.
# scripts/routine-update checks this file explicitly and fails if that changes.
set -e
export AWS_PAGER=""
REGION=us-east-1
aws ec2 terminate-instances --region $REGION --instance-ids i-0928bd7b9132d2902
aws ec2 wait instance-terminated --region $REGION --instance-ids i-0928bd7b9132d2902
aws ec2 release-address --region $REGION --allocation-id eipalloc-01a88a6a86d40f7d2
aws ec2 delete-security-group --region $REGION --group-id sg-08fc60a999ccf6d18 2>/dev/null || true
echo "demo host torn down."
