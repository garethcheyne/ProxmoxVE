#!/usr/bin/env bash

#Copyright (c) 2021-2025 community-scripts ORG
# Author: Michel Roegl-Brunner (michelroegl-brunner)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://checkmate.so/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

function generate_jwt_secret() {
  msg_info "Generating secure JWT secret"

  # Generate a random 32-character string for JWT secret
  # Using multiple sources of entropy for better randomness
  if command -v openssl >/dev/null 2>&1; then
    # Use OpenSSL if available (most secure)
    JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
  else
    # Fallback to built-in bash methods
    JWT_SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)

    # If /dev/urandom isn't available, use date+hostname as seed (least secure)
    if [ -z "$JWT_SECRET" ]; then
      JWT_SECRET=$(echo "$(date +%s%N)$HOSTNAME" | md5sum | head -c 32)
    fi
  fi

  msg_ok "Generated secure JWT secret"

  # Return the generated secret
  echo "$JWT_SECRET"
}

function install_docker() {
  msg_info "Installing Docker"

  # Check if Docker is already installed
  if command -v docker >/dev/null 2>&1; then
    msg_ok "Docker already installed"
  else
    # Install prerequisites
    $STD apt-get update
    $STD apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg \
      lsb-release

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

    # Install Docker
    $STD apt-get update
    $STD apt-get install -y docker-ce docker-ce-cli containerd.io

    # Install Docker Compose
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    msg_ok "Installed Docker and Docker Compose"
  fi
}

function create_env_file() {
  msg_info "Creating .env file"

  # Get the IP address of the host
  HOST_IP=$(hostname -I | awk '{print $1}')

  # Generate a secure JWT secret
  JWT_SECRET=$(generate_jwt_secret)

  # Create .env file with all required variables
  cat >/opt/checkmate/.env <<EOL
UPTIME_APP_API_BASE_URL=/api/v1
UPTIME_APP_CLIENT_HOST=http://${HOST_IP}
CLIENT_HOST=http://${HOST_IP}
DB_CONNECTION_STRING=mongodb://mongodb:27017/uptime_db?replicaSet=rs0
REDIS_URL=redis://redis:6379
JWT_SECRET=${JWT_SECRET}
EOL

  msg_ok "Created .env file"
}

function update_dockercompose() {
  msg_info "Updating Docker Compose file"

  # Create backup of original file
  cp /opt/checkmate/docker-compose.yaml /opt/checkmate/docker-compose.yaml.bak

  # Create a temporary file for processing
  grep -v "UPTIME_APP_API_BASE_URL\|UPTIME_APP_CLIENT_HOST\|CLIENT_HOST\|DB_CONNECTION_STRING\|REDIS_URL\|JWT_SECRET" /opt/checkmate/docker-compose.yaml >/tmp/docker-compose.tmp

  # Replace environment section with a reference to the .env file
  awk '{
    print $0;
    if ($0 ~ /environment:/) {
      print "      - .env";
      getline; # Skip to next line after environment:
      while ($0 ~ /^      - /) {
        getline; # Skip environment variable lines
      }
      print $0; # Print the next non-environment line
    }
  }' /tmp/docker-compose.tmp >/opt/checkmate/docker-compose.yaml

  # Update port binding to use 0.0.0.0
  sed -i "s/- \".*:52345\"/- \"0.0.0.0:52345:52345\"/" /opt/checkmate/docker-compose.yaml

  # Add env_file directive to the services.server section
  sed -i '/services:/,/server:/{s/server:/server:\n    env_file: .env/}' /opt/checkmate/docker-compose.yaml

  # Remove the global env_file if it exists (to avoid duplication)
  sed -i '/^  env_file: .env/d' /opt/checkmate/docker-compose.yaml

  rm /tmp/docker-compose.tmp

  msg_ok "Updated Docker Compose file"
}

function install_checkmate() {

  msg_info "Installing Checkmate"

  # Create directory for Checkmate
  mkdir -p /opt/checkmate

  # Download the docker-compose.yaml file
  msg_info "Downloading Docker Compose configuration"
  curl -fsSL "https://raw.githubusercontent.com/bluewave-labs/Checkmate/develop/docker/dist-mono/docker-compose.yaml" -o "/opt/checkmate/docker-compose.yaml"

  # Modify docker-compose.yaml to set environment variables
  msg_info "Configuring Docker Compose for external access"

  # Create .env file with required variables
  create_env_file

  # Update the docker-compose.yaml file
  update_dockercompose

  # Make sure the data directory exists with proper permissions
  mkdir -p /opt/checkmate/data
  chmod 777 /opt/checkmate/data

  # Start Checkmate services
  msg_info "Starting Checkmate services"
  cd /opt/checkmate || exit
  docker-compose up -d

  # Record the installation
  CHECKMATE_VERSION="$(date +%Y%m%d)"
  echo "${CHECKMATE_VERSION}" >"/opt/checkmate_version.txt"

  msg_ok "Installed Checkmate"
}

function create_update_ip_script() {
  msg_info "Creating IP update script"

  # Create the update script in the Checkmate directory
  cat >/opt/checkmate/update-ip.sh <<'EOL'
#!/usr/bin/env bash

# Log file for output
LOG_FILE="/opt/checkmate/ip-update.log"

# Get timestamp for logging
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Function to log messages
log_message() {
  echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
}

log_message "Running IP address update check"

# Get current IP address
CURRENT_IP=$(hostname -I | awk '{print $1}')
log_message "Current IP address: $CURRENT_IP"

# Check if .env file exists
if [ -f /opt/checkmate/.env ]; then
  # Extract IP from existing .env file
  ENV_IP=$(grep "UPTIME_APP_API_BASE_URL" /opt/checkmate/.env | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+")
  log_message "IP address in .env file: $ENV_IP"
  
  # Check if IP has changed
  if [ "$CURRENT_IP" != "$ENV_IP" ]; then
    log_message "IP address has changed from $ENV_IP to $CURRENT_IP"
    
    # Create backup of current .env file
    cp /opt/checkmate/.env /opt/checkmate/.env.bak
    log_message "Created backup of .env file"
    
    # Update .env file with new IP
    sed -i "s/$ENV_IP/$CURRENT_IP/g" /opt/checkmate/.env
    log_message "Updated IP address in .env file"
    
    # Restart containers to apply changes
    if command -v docker-compose >/dev/null 2>&1 && [ -f /opt/checkmate/docker-compose.yaml ]; then
      log_message "Restarting Docker containers to apply changes"
      cd /opt/checkmate || exit
      docker-compose down
      docker-compose up -d
      log_message "Restarted Docker containers"
    else
      log_message "WARNING: Docker Compose not found or docker-compose.yaml missing"
    fi
    
    log_message "IP address update completed successfully"
  else
    log_message "No IP address change detected"
  fi
else
  log_message "ERROR: .env file not found at /opt/checkmate/.env"
fi
EOL

  # Make the script executable
  chmod +x /opt/checkmate/update-ip.sh
  msg_ok "Created IP update script at /opt/checkmate/update-ip.sh"
}

function setup_systemd_service() {
  msg_info "Setting up systemd service for IP updates"

  # Create systemd service file
  cat >/etc/systemd/system/checkmate-ip-update.service <<EOL
[Unit]
Description=Checkmate IP Update Service
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/checkmate/update-ip.sh
WorkingDirectory=/opt/checkmate

[Install]
WantedBy=multi-user.target
EOL

  # Create systemd timer for scheduled runs
  cat >/etc/systemd/system/checkmate-ip-update.timer <<EOL
[Unit]
Description=Run Checkmate IP Update Service on boot and hourly

[Timer]
OnBootSec=60
OnUnitActiveSec=3600
Unit=checkmate-ip-update.service

[Install]
WantedBy=timers.target
EOL

  # Enable and start the timer
  systemctl daemon-reload
  systemctl enable checkmate-ip-update.timer
  systemctl start checkmate-ip-update.timer

  msg_ok "Set up systemd service and timer for automatic IP updates"
}

function update_checkmate_docker() {
  msg_info "Updating Checkmate Docker containers"

  # Check if Checkmate is installed
  if [[ ! -d /opt/checkmate ]]; then
    msg_error "No Checkmate installation found!"
    return 1
  fi

  # Navigate to the Checkmate directory
  cd /opt/checkmate || exit

  # Pull latest Docker images
  msg_info "Pulling latest Docker images"
  $STD docker-compose pull

  # Stop existing containers
  msg_info "Stopping current containers"
  $STD docker-compose down

  # Start containers with new images
  msg_info "Starting containers with updated images"
  $STD docker-compose up -d

  # Update version timestamp
  CHECKMATE_VERSION="$(date +%Y%m%d)"
  echo "${CHECKMATE_VERSION}" >"/opt/checkmate_version.txt"

  msg_ok "Updated Checkmate Docker containers"
}
# Create a separate update script that can be run later
function create_update_script() {
  msg_info "Creating update script"

  cat >/usr/local/bin/update-checkmate.sh <<'EOL'
#!/usr/bin/env bash

# Log file for output
LOG_FILE="/opt/checkmate/update.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Function for logging
log_message() {
  echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
}

log_message "Starting Checkmate update"

# Check if Checkmate is installed
if [[ ! -d /opt/checkmate ]]; then
  log_message "ERROR: No Checkmate installation found!"
  exit 1
fi

# Navigate to the Checkmate directory
cd /opt/checkmate || exit

# Pull latest Docker images
log_message "Pulling latest Docker images"
docker-compose pull

# Stop existing containers
log_message "Stopping current containers"
docker-compose down

# Start containers with new images
log_message "Starting containers with updated images"
docker-compose up -d

# Update version timestamp
CHECKMATE_VERSION="$(date +%Y%m%d)"
echo "${CHECKMATE_VERSION}" >"/opt/checkmate_version.txt"

log_message "Checkmate update completed successfully"
echo "Checkmate update completed successfully. See ${LOG_FILE} for details."
EOL

  chmod +x /usr/local/bin/update-checkmate.sh

  # Create a systemd service for updates
  cat >/etc/systemd/system/checkmate-update.service <<EOL
[Unit]
Description=Checkmate Update Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-checkmate.sh
WorkingDirectory=/opt/checkmate

[Install]
WantedBy=multi-user.target
EOL

  # Create a weekly timer for updates
  cat >/etc/systemd/system/checkmate-update.timer <<EOL
[Unit]
Description=Run Checkmate Update weekly

[Timer]
OnCalendar=Sun 03:00:00
Persistent=true
Unit=checkmate-update.service

[Install]
WantedBy=timers.target
EOL

  # Enable the timer
  systemctl daemon-reload
  systemctl enable checkmate-update.timer
  systemctl start checkmate-update.timer

  msg_ok "Created update script at /usr/local/bin/update-checkmate.sh and scheduled weekly updates"
}

function setup_ip_monitoring() {
  # Create the update script
  create_update_ip_script

  # Set up systemd service and timer
  setup_systemd_service

  msg_info "IP monitoring setup complete"
}

color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

install_docker
install_checkmate
setup_ip_monitoring
create_update_script

msg_info "Checkmate Installation Complete"

motd_ssh

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
