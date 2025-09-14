#!/bin/bash
set -e

echo "Updating package index..."
sudo apt-get update -y

echo "Installing base dependencies..."
sudo apt install net-tools -y
sudo apt-get install -y \
  bash \
  curl \
  git \
  openssh-server \
  openssh-client \
  python3 \
  python3-pip \
  openjdk-17-jre \
  nodejs \
  npm \
  jq \
  wget \
  php-cli \
  php-mbstring \
  php-xml \
  php-curl \
  php-json \
  php-tokenizer \
  php-zip \
  php-ctype \
  unzip \
  ca-certificates \
  gnupg \
  lsb-release \
  software-properties-common

echo "Starting and enabling SSH service..."
sudo systemctl start ssh
sudo systemctl enable ssh

echo "Setting up Docker repository and GPG key..."

sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Updating package index (with Docker repo)..."
sudo apt-get update -y

echo "Installing Docker Engine..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

echo "Configuring Docker daemon with insecure registries..."
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
    "insecure-registries": ["192.168.146.133:5000"],
    "registry-mirrors": ["http://192.168.146.133:5000"]
}
EOF

echo "Starting and enabling Docker service..."
sudo systemctl daemon-reload
sudo systemctl start docker
sudo systemctl enable docker

echo "Restarting Docker to apply daemon configuration..."
sudo systemctl restart docker

echo "Installing Docker Compose (latest release)..."
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
if [ ! -L /usr/bin/docker-compose ]; then
  sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
else
  echo "Symbolic link /usr/bin/docker-compose already exists"
fi

echo "Creating Jenkins user (locked password)..."
if ! id -u jenkins >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash jenkins
  sudo passwd -l jenkins
  echo "Created Jenkins user with locked password (no login)"
else
  echo "Jenkins user already exists"
fi

echo "Adding Jenkins user to Docker group..."
sudo usermod -aG docker jenkins

echo "Adding Jenkins user to sudo group..."
sudo usermod -aG sudo jenkins

echo "Giving Jenkins user passwordless sudo access..."
echo "jenkins ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/jenkins

echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

echo "Installing Trivy..."
TRIVY_VERSION=0.66.0
wget https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz -O trivy.tar.gz
tar -zxvf trivy.tar.gz
sudo mv trivy /usr/local/bin/
rm trivy.tar.gz

echo "Installing Semgrep..."
sudo snap install semgrep

echo "Installing OWASP ZAP..."
ZAP_VERSION=2.15.0
wget https://github.com/zaproxy/zaproxy/releases/download/v${ZAP_VERSION}/ZAP_${ZAP_VERSION}_Linux.tar.gz -O zap.tar.gz
sudo tar -xzf zap.tar.gz -C /opt
rm zap.tar.gz
echo "Please add /opt/ZAP_${ZAP_VERSION} to your PATH environment variable to run OWASP ZAP"

echo "Installing PHPStan and PHPCS globally for Jenkins user..."
sudo -u jenkins composer global require phpstan/phpstan squizlabs/php_codesniffer
JENKINS_COMPOSER_BIN_DIR=$(sudo -u jenkins composer global config bin-dir --absolute)
if [ -f "$JENKINS_COMPOSER_BIN_DIR/phpstan" ]; then
  sudo chmod +x "$JENKINS_COMPOSER_BIN_DIR/phpstan"
fi
if [ -f "$JENKINS_COMPOSER_BIN_DIR/phpcs" ]; then
  sudo chmod +x "$JENKINS_COMPOSER_BIN_DIR/phpcs"
fi

JENKINS_PROFILE="/var/lib/jenkins/.profile"
EXPORT_LINE="export PATH=\"$JENKINS_COMPOSER_BIN_DIR:\$PATH\""
sudo grep -qxF "$EXPORT_LINE" "$JENKINS_PROFILE" || echo "$EXPORT_LINE" | sudo tee -a "$JENKINS_PROFILE"

echo "PATH for Composer global binaries added permanently to Jenkins user's profile."
echo "Path: $JENKINS_COMPOSER_BIN_DIR"
echo "Profile: $JENKINS_PROFILE"

echo "Installation complete. Docker, Docker Compose, Jenkins user (locked password), and all tools are ready."
echo "Jenkins user can run Docker and sudo commands without password."
echo "Please log out and log back in or restart the system to ensure all group changes take effect."
