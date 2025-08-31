pipeline {
    agent any

    environment {
        REGISTRY_URL = 'localhost:5000'
        DOCKER_CREDENTIALS_ID = 'dockerRegistry' // Jenkins Credentials ID for Docker registry
        IMAGE_NAME = "${REGISTRY_URL}/dvwa:${env.GIT_COMMIT ?: 'latest'}"
        DEPLOY_PORT = env.BRANCH_NAME == 'prod' ? '8082' : '8081'
        DEPLOY_NETWORK = env.BRANCH_NAME == 'prod' ? 'prod_net' : 'uat_net'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
    }

    stages {
        stage('Checkout Source') {
            steps {
                checkout([$class: 'GitSCM', branches: [[name: "refs/heads/${env.BRANCH_NAME}"]],
                    userRemoteConfigs: [[url: 'https://github.com/your-org/your-dvwa-repo.git']]])
            }
        }

        stage('Build and Scan in Docker') {
            steps {
                script {
                    docker.image("${REGISTRY_URL}/jenkins-agent-dvwa:latest").inside('--privileged -v /var/run/docker.sock:/var/run/docker.sock') {
                        dir('vulnerabilities/api') {
                            sh 'composer install --no-interaction --no-progress --no-suggest --prefer-dist'
                        }

                        dir('vulnerabilities/api') {
                            withSonarQubeEnv('SonarQube') {
                                script {
                                    if (fileExists('sonar-project.properties')) {
                                        sh 'sonar-scanner'
                                    } else if (sh(script: 'command -v phpstan', returnStatus: true) == 0) {
                                        sh 'phpstan analyse .'
                                    } else if (sh(script: 'command -v phpcs', returnStatus: true) == 0) {
                                        sh 'phpcs .'
                                    } else {
                                        error "No code quality tool found: sonar-scanner, phpstan, or phpcs"
                                    }
                                }
                            }
                        }

                        sh 'semgrep --config=auto vulnerabilities/api --output semgrep-report.sarif'
                        archiveArtifacts 'semgrep-report.sarif'

                        if (fileExists('vulnerabilities/api/composer.lock')) {
                            sh 'trivy fs vulnerabilities/api --severity CRITICAL --exit-code 1'
                        } else {
                            echo "Skipping SCA scan: composer.lock not found"
                        }
                        archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true

                        // Docker login
                        docker.withRegistry("http://${REGISTRY_URL}", DOCKER_CREDENTIALS_ID) {
                            echo "Logged into Docker registry ${REGISTRY_URL}"
                        }

                        // Build Docker image
                        sh """
                            docker build --no-cache --pull \
                            --label commit=${env.GIT_COMMIT} \
                            --label branch=${env.BRANCH_NAME} \
                            --label build_url=${env.BUILD_URL} \
                            -t ${IMAGE_NAME} .
                        """

                        // Image scan
                        sh "trivy image --severity CRITICAL --exit-code 1 ${IMAGE_NAME}"

                        // Push Docker image
                        docker.withRegistry("http://${REGISTRY_URL}", DOCKER_CREDENTIALS_ID) {
                            sh "docker push ${IMAGE_NAME}"
                        }
                    }
                }
            }
        }

        stage('Deploy') {
            when {
                anyOf {
                    branch 'dev'
                    branch 'prod'
                }
            }
            steps {
                script {
                    if (env.BRANCH_NAME == 'prod') {
                        input message: "Approve PROD deployment"
                    }
                    sh """
                        docker network create ${DEPLOY_NETWORK} || true
                        docker-compose -f docker-compose-${env.BRANCH_NAME}.yml up -d
                    """
                }
            }
        }

        stage('DAST') {
            steps {
                script {
                    if (env.BRANCH_NAME == 'prod') {
                        sh """
                            docker run --rm -v \$PWD:/zap/wrk -t owasp/zap2docker-stable \
                            zap-baseline.py -t http://localhost:${DEPLOY_PORT} -g gen.conf -r zap_report.html -J -w 2
                        """
                    } else {
                        sh """
                            docker run --rm -v \$PWD:/zap/wrk -t owasp/zap2docker-stable \
                            zap-baseline.py -t http://localhost:${DEPLOY_PORT} -g gen.conf -r zap_report.html || exit 1
                        """
                    }
                }
                archiveArtifacts artifacts: 'zap_report.html', allowEmptyArchive: true
            }
        }

        stage('Publish Reports') {
            steps {
                publishHTML([
                    reportDir: '.',
                    reportFiles: 'zap_report.html',
                    reportName: 'ZAP Report',
                    keepAll: true,
                    alwaysLinkToLastBuild: false,
                    allowMissing: true
                ])
            }
        }
    }

    post {
        always {
            script {
                node {
                    sh 'docker-compose down || true'
                }
            }
        }
        success {
            echo "Pipeline completed successfully"
        }
        failure {
            echo "Pipeline failed. Check logs."
        }
    }
}
