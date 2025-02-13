#!/usr/bin/env bash
# This script setups dockerized Redash on Ubuntu 20.04.
set -eu

REDASH_BASE_PATH=/opt/redash

install_docker() {
  echo "Installing Docker..."
  # Install Docker
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get -qqy update
  DEBIAN_FRONTEND=noninteractive sudo -E apt-get -qqy -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
  sudo apt-get -yy install apt-transport-https ca-certificates curl software-properties-common pwgen gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=""$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    ""$(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
    sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Install Docker Compose
  sudo ln -sfv /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

  # Allow current user to run Docker commands
  sudo usermod -aG docker "$USER"
}

create_directories() {
  echo "Creating Redash Directories..."
  if [ ! -e "$REDASH_BASE_PATH" ]; then
    sudo mkdir -p "$REDASH_BASE_PATH"
    sudo chown "$USER:" "$REDASH_BASE_PATH"
  fi

  if [ ! -e "$REDASH_BASE_PATH"/postgres-data ]; then
    mkdir "$REDASH_BASE_PATH"/postgres-data
  fi
}

create_config() {
  echo "Creating Config File..."
  if [ -e "$REDASH_BASE_PATH"/env ]; then
    rm "$REDASH_BASE_PATH"/env
    touch "$REDASH_BASE_PATH"/env
  fi

  COOKIE_SECRET=$(pwgen -1s 32)
  SECRET_KEY=$(pwgen -1s 32)
  POSTGRES_PASSWORD=$(pwgen -1s 32)
  REDASH_DATABASE_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres/postgres"

  cat <<EOF >"$REDASH_BASE_PATH"/env
PYTHONUNBUFFERED=0
REDASH_LOG_LEVEL=INFO
REDASH_REDIS_URL=redis://redis:6379/0
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REDASH_COOKIE_SECRET=$COOKIE_SECRET
REDASH_SECRET_KEY=$SECRET_KEY
REDASH_DATABASE_URL=$REDASH_DATABASE_URL
REDASH_RATELIMIT_ENABLED=false
EOF
}

setup_compose() {
  echo "Setting up Docker Compose..."
  cp /tmp/docker-compose.yml $REDASH_BASE_PATH
  cd "$REDASH_BASE_PATH"
  echo "export COMPOSE_PROJECT_NAME=redash" >>~/.profile
  echo "export COMPOSE_FILE=/$REDASH_BASE_PATH/docker-compose.yml" >>~/.profile
  export COMPOSE_PROJECT_NAME=redash
  export COMPOSE_FILE=/$REDASH_BASE_PATH/docker-compose.yml
  echo "Provisioning Redash Database..."
  sudo docker-compose run --rm server create_db
  echo "Starting Redash..."
  sudo docker-compose up -d
}

create_crontab() {
cat >/etc/cron.daily/log_cleanup <<EOF
#!/bin/sh
rm -rf /var/log/.gz;
sudo journalctl --rotate;
sudo journalctl --vacuum-time=1hour;
EOF
chmod +x /etc/cron.daily/log_cleanup
}
install_docker
create_directories
create_config
setup_compose
create_crontab
