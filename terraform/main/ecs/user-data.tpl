#!/bin/bash -xe
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Update the system
yum update -y

# Install AWS CLI
yum install -y aws-cli

# Configure ECS agent
systemctl restart docker
echo ECS_CLUSTER=${ecs_cluster_name} >> /etc/ecs/ecs.config

# Variables for Postgres
PG_HOST="localhost"
PG_PORT="5432"
PG_USER="postgres"
PG_DB="postgres"
PG_PASSWORD=$(openssl rand -base64 16)

# Put the Postgres credentials in a secret
SECRET_NAME="devopsdemo-postgres-credentials"
aws secretsmanager update-secret --region ${aws_region} --secret-id ${postgres_secret_name} --secret-string "$(cat <<EOF
{
  "host": "$PG_HOST",
  "port": "$PG_PORT",
  "username": "$PG_USER",
  "password": "$PG_PASSWORD",
  "database": "$PG_DB"
}
EOF
)"

# Install Postgres
amazon-linux-extras install -y postgresql14
yum install -y postgresql-server
su - postgres -c "/usr/bin/initdb -D /var/lib/pgsql/data"
systemctl start postgresql
systemctl enable postgresql

# Set the Postgres user password
su - postgres -c "psql -c \"ALTER USER postgres WITH PASSWORD '$PG_PASSWORD';\""

# Test Postgre connection
psql -h $PG_HOST -p $PG_PORT -U $PG_USER -d $PG_DB -c "SELECT 1;"

# Capture the exit status of the psql command
status=$?

if [ $status -eq 0 ]; then
  echo PostgreSQL connection successful!
else
  echo PostgreSQL connection failed!
fi



# Set up Cron
cat <<'EOF' > /usr/local/bin/start_deployment.sh

#!/bin/bash -xe

# Set the necessary variables
REGISTRY="ghcr.io/devopsdemo/devops-demo-app"
PIPELINE="devopsdemo-pipeline"

# Pull the latest Docker image
docker pull $REGISTRY:latest

# Get the latest image hash
IMAGE_HASH=$(docker inspect --format='{{index .RepoDigests 0}}' $REGISTRY:latest)
echo "Latest image hash: $IMAGE_HASH"

# Start the deployment pipeline
aws codepipeline start-pipeline-execution --region ${aws_region} $PIPELINE

echo "Deployment updated with the latest image: $IMAGE_HASH"
EOF

# Make the script executable
chmod +x /usr/local/bin/start_deployment.sh

# Create a cron job to run the script every hour
crontab -l | { cat; echo "0 * * * * /usr/local/bin/start_deployment.sh >> /var/log/start_deployment.log 2>&1"; } | crontab -

echo User Data script completed on `date`