#!/bin/bash
set -e

echo "Updating package index..."
sudo apt-get update -y

echo "Installing base dependencies..."
sudo apt-get install -y \
  bash \
  curl \
  git \
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
  unzip  # unzip used by composer sometimes

echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

echo "Installing Trivy..."
TRIVY_VERSION=0.65.0
wget https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz -O trivy.tar.gz
tar -zxvf trivy.tar.gz
sudo mv trivy /usr/local/bin/
rm trivy.tar.gz

echo "Installing Semgrep..."
sudo pip3 install --no-cache-dir semgrep

echo "Installing OWASP ZAP..."
ZAP_VERSION=2.16.1
wget https://github.com/zaproxy/zaproxy/releases/download/v${ZAP_VERSION}/ZAP_${ZAP_VERSION}_Linux.tar.gz -O zap.tar.gz
sudo tar -xzf zap.tar.gz -C /opt
rm zap.tar.gz
echo "Please add /opt/ZAP_${ZAP_VERSION} to your PATH environment variable to run OWASP ZAP"

echo "Installing docker-compose..."
sudo curl -L "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

echo "Installing PHPStan and PHPCS globally for Jenkins user..."
# Run as jenkins user (adjust if needed)
sudo -u jenkins composer global require phpstan/phpstan squizlabs/php_codesniffer
sudo chmod +x /home/jenkins/.composer/vendor/bin/phpstan /home/jenkins/.composer/vendor/bin/phpcs

echo "Installation complete. Please ensure Docker engine is installed and running separately."

