#!/bin/bash
set -euo pipefail

# Retrieve DB credentials from Secrets Manager (no plaintext passwords in scripts)
SECRET_ARN=$(aws ssm get-parameter \
  --name "/bookstore/rds/secret-arn" \
  --query "Parameter.Value" \
  --output text \
  --region us-east-1)

SECRET=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text \
  --region us-east-1)

export DB_HOST=$(echo "$SECRET" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host'].split(':')[0])")
export DB_USER=$(echo "$SECRET" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['username'])")
export DB_PASS=$(echo "$SECRET" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['password'])")

# Initialize database schema
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" test < /home/ubuntu/aws_three_tier_code/backend/test.sql

# Start backend with PM2
sudo pm2 startup
sudo env PATH=$PATH:/usr/bin /usr/bin/pm2 startup systemd -u ubuntu --hp /home/ubuntu
sudo systemctl start pm2-root
sudo systemctl enable pm2-root
sudo pm2 start /home/ubuntu/aws_three_tier_code/backend/index.js --name "backendApi"
sudo pm2 save
