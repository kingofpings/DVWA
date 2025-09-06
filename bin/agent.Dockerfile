FROM docker:24.0.5-dind

# Install utilities and dependencies
RUN apk add --no-cache \
    bash \
    curl \
    git \
    openssh-client \
    python3 \
    py3-pip \
    openjdk17-jre \
    nodejs npm \
    jq

# install php and required extensions including openssl and ctype
RUN apk add --no-cache \
    php php-cli php-phar php-mbstring php-xml php-curl php-json php-tokenizer php-zip php-openssl php-ctype

# Install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install Trivy (container and fs scanner)
ENV TRIVY_VERSION=0.65.0
RUN wget https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz -O trivy.tar.gz \
    && tar -zxvf trivy.tar.gz \
    && mv trivy /usr/local/bin/ \
    && rm trivy.tar.gz

# Install Semgrep
RUN pip3 install semgrep

# Install OWASP ZAP
ENV ZAP_VERSION=2.16.1
RUN curl -L https://github.com/zaproxy/zaproxy/releases/download/v${ZAP_VERSION}/ZAP_${ZAP_VERSION}_Linux.tar.gz -o zap.tar.gz \
    && tar -xzf zap.tar.gz -C /opt \
    && rm zap.tar.gz

ENV PATH="/opt/ZAP_${ZAP_VERSION}:${PATH}"

# Setup Jenkins user with UID and GID 1000
RUN addgroup -g 1000 -S jenkins && \
    adduser -u 1000 -S jenkins -G jenkins

RUN mkdir -p /var/lib/jenkins \
    && chown -R jenkins:jenkins /var/lib/jenkins \
    && chmod -R 755 /var/lib/jenkins \
    && mkdir -p /home/jenkins/.composer && chown -R jenkins:jenkins /home/jenkins

USER jenkins

RUN composer global require phpstan/phpstan squizlabs/php_codesniffer \
    && chmod +x /home/jenkins/.composer/vendor/bin/phpstan /home/jenkins/.composer/vendor/bin/phpcs
ENV PATH="/home/jenkins/.composer/vendor/bin:${PATH}" \
    JENKINS_HOME=/var/lib/jenkins

ENV JENKINS_HOME=/var/lib/jenkins
ENV PATH="/var/lib/jenkins/.local/bin:${PATH}"
WORKDIR /home/jenkins

# Entrypoint to keep the container running (optional)
CMD ["sleep", "infinity"]
