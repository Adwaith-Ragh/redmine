#!/usr/bin/env bash
set -e

REDMINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REDMINE_DIR"

echo "Waiting for Redmine server to be responsive on http://localhost:3005..."
max_retries=60
count=0
until curl -s -f -o /dev/null http://localhost:3005; do
  sleep 2
  count=$((count + 1))
  if [ $count -ge $max_retries ]; then
    echo "Error: Redmine did not become responsive after 120 seconds."
    exit 1
  fi
  printf "."
done
echo " Redmine is up!"

echo "Running Redmine seeding script..."
docker compose exec -T redmine bin/rails runner /seed.rb

echo ""
echo "Redmine initialization and seeding complete!"
echo "Access Redmine Web UI: http://localhost:3005"
echo "Admin Login: admin / AdminPassword123!"
echo "API Service Key: fedcba9876543210fedcba9876543210fedcba98"
