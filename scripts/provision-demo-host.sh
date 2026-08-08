#!/bin/bash
# Provisions the Pockterm App Review demo SSH host.
#
# App Review will actually try to connect — an SSH client with no reachable
# demo server is a Guideline 2.1 rejection. Run this before submitting, and
# scripts/teardown-demo-host.sh after approval.
#
# Credentials are written to ~/Documents/Apps/pockterm/demo-host.txt, OUTSIDE
# the repo. This repository is public and a demo password was committed to it
# once already; never paste the real values into docs/app-store-metadata.md.
#
# NEVER put AWS credentials in this file. It authenticates from the ambient AWS
# CLI config (~/.aws/credentials, outside the repo) — no keys, no --profile, no
# exported AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY. This repository is PUBLIC.
# scripts/routine-update checks this file explicitly and fails if that changes.
set -euo pipefail
export AWS_PAGER=""

REGION=us-east-1
NAME=pockterm-demo
CRED_FILE="$HOME/Documents/Apps/pockterm/demo-host.txt"
TEARDOWN="$(cd "$(dirname "$0")" && pwd)/teardown-demo-host.sh"

echo "==> generating demo password"
# Ambiguous characters removed: a reviewer may be typing this on a phone.
# pipefail is off for this line only: head closes the pipe, tr takes SIGPIPE,
# and the pipeline would otherwise report failure and kill the script.
set +o pipefail
PASSWORD="Review-$(LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' </dev/urandom | head -c 16)"
set -o pipefail

echo "==> resolving latest Amazon Linux 2023 arm64 AMI"
AMI=$(aws ssm get-parameters --region "$REGION" \
    --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
    --query 'Parameters[0].Value' --output text)
echo "    $AMI"

echo "==> security group"
VPC=$(aws ec2 describe-vpcs --region "$REGION" --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' --output text)
SG=$(aws ec2 create-security-group --region "$REGION" --group-name "$NAME-$(date +%s)" \
    --description "Pockterm App Review demo host" --vpc-id "$VPC" \
    --query 'GroupId' --output text)
# App Review connects from wherever Apple happens to be; 22 must be open.
aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
echo "    $SG"

echo "==> launching t4g.nano"
USER_DATA=$(cat <<EOF
#!/bin/bash
useradd -m -s /bin/bash demo
echo 'demo:${PASSWORD}' | chpasswd
# Cloud-init writes PasswordAuthentication no in 50-cloud-init.conf; this file
# sorts after it and wins.
cat > /etc/ssh/sshd_config.d/99-pockterm-demo.conf <<'SSHD'
PasswordAuthentication yes
PermitRootLogin no
SSHD
systemctl restart sshd
echo 'Welcome to the Pockterm review demo host.' > /etc/motd
EOF
)
INSTANCE=$(aws ec2 run-instances --region "$REGION" --image-id "$AMI" \
    --instance-type t4g.nano --security-group-ids "$SG" \
    --user-data "$USER_DATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
    --query 'Instances[0].InstanceId' --output text)
echo "    $INSTANCE"

echo "==> waiting for it to run"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE"

echo "==> elastic IP"
ALLOC=$(aws ec2 allocate-address --region "$REGION" --domain vpc \
    --query 'AllocationId' --output text)
aws ec2 associate-address --region "$REGION" --instance-id "$INSTANCE" \
    --allocation-id "$ALLOC" >/dev/null
IP=$(aws ec2 describe-addresses --region "$REGION" --allocation-ids "$ALLOC" \
    --query 'Addresses[0].PublicIp' --output text)
echo "    $IP"

echo "==> waiting for sshd (user-data has to finish first)"
for i in $(seq 1 40); do
    if nc -z -G5 "$IP" 22 2>/dev/null; then break; fi
    sleep 10
done

echo "==> writing credentials to $CRED_FILE"
mkdir -p "$(dirname "$CRED_FILE")"
cat > "$CRED_FILE" <<EOF
Pockterm App Review demo host — provisioned $(date -u +%Y-%m-%dT%H:%M:%SZ)

    Host: $IP
    Port: 22
    Username: demo
    Password: $PASSWORD

instance: $INSTANCE
security-group: $SG
eip-allocation: $ALLOC
region: $REGION

Paste these into the App Store Connect review-notes field. NEVER commit them.
Tear down after approval: scripts/teardown-demo-host.sh
EOF
chmod 600 "$CRED_FILE"

echo "==> updating teardown script with the new resource ids"
cat > "$TEARDOWN" <<EOF
#!/bin/bash
# Tears down the Pockterm App Review demo SSH host. Run AFTER the app is approved.
# Written by scripts/provision-demo-host.sh on $(date -u +%Y-%m-%d).
#
# NEVER put AWS credentials in this file. It authenticates from the ambient AWS
# CLI config (~/.aws/credentials, outside the repo) — no keys, no --profile, no
# exported AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY. This repository is PUBLIC.
# scripts/routine-update checks this file explicitly and fails if that changes.
set -e
export AWS_PAGER=""
REGION=$REGION
aws ec2 terminate-instances --region \$REGION --instance-ids $INSTANCE
aws ec2 wait instance-terminated --region \$REGION --instance-ids $INSTANCE
aws ec2 release-address --region \$REGION --allocation-id $ALLOC
aws ec2 delete-security-group --region \$REGION --group-id $SG 2>/dev/null || true
echo "demo host torn down."
EOF
chmod +x "$TEARDOWN"

echo
echo "demo host ready at $IP — credentials in $CRED_FILE"
echo "verify with:  ssh demo@$IP"
