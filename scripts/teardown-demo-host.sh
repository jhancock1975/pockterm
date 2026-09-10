#!/bin/bash
# Tears down the Pockterm App Review demo SSH host. Run AFTER the app is approved.
# Written by scripts/provision-demo-host.sh on 2026-09-09.
#
# NEVER put AWS credentials in this file. It authenticates from the ambient AWS
# CLI config (~/.aws/credentials, outside the repo) — no keys, no --profile, no
# exported AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY. This repository is PUBLIC.
# scripts/routine-update checks this file explicitly and fails if that changes.
set -e
export AWS_PAGER=""
REGION=us-east-1
aws ec2 terminate-instances --region $REGION --instance-ids i-0c7c6164a4b6673b5
aws ec2 wait instance-terminated --region $REGION --instance-ids i-0c7c6164a4b6673b5
aws ec2 release-address --region $REGION --allocation-id eipalloc-0efb1763454194cd7
aws ec2 delete-security-group --region $REGION --group-id sg-091f0843de17f4487 2>/dev/null || true
echo "demo host torn down."
