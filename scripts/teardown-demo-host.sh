#!/bin/bash
# Tears down the Pockterm App Review demo SSH host. Run AFTER the app is approved.
# Written by scripts/provision-demo-host.sh on 2026-08-08.
#
# NEVER put AWS credentials in this file. It authenticates from the ambient AWS
# CLI config (~/.aws/credentials, outside the repo) — no keys, no --profile, no
# exported AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY. This repository is PUBLIC.
# scripts/routine-update checks this file explicitly and fails if that changes.
set -e
export AWS_PAGER=""
REGION=us-east-1
aws ec2 terminate-instances --region $REGION --instance-ids i-091139cee342946bc
aws ec2 wait instance-terminated --region $REGION --instance-ids i-091139cee342946bc
aws ec2 release-address --region $REGION --allocation-id eipalloc-00fdbb5f8377a56f1
aws ec2 delete-security-group --region $REGION --group-id sg-01f97cb65642f6b63 2>/dev/null || true
echo "demo host torn down."
