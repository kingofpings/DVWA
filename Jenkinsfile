pipeline {
    agent any

    environment {
        DOCKER_IMAGE = "dvwa:${env.GIT_COMMIT}"
        DOCKER_IMAGE_BRANCH = "dvwa:${env.BRANCH_NAME}"
        LOCAL_REGISTRY = "localhost:5000"
        DEPLOY_PORT = '8081'    // default, overridden for prod in stage
        DEPLOY_NETWORK = 'uat_net' // default
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        skipDefaultCheckout()
    }

    stages {
        stage('Set Environment') {
            steps {
                script {
                    if (env.BRANCH_NAME == 'prod') {
                        env.DEPLOY_PORT = '8082'
                        env.DEPLOY_NETWORK = 'prod_net'
                    }
                }
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
                // Inspect tags & composer.lock presence
                docker.image('alpine/git').inside {
                    sh 'git fetch --tags'
                    sh 'git tag -l'
                    sh '''
                    if [ -f vulnerabilities/api/composer.lock ]; then
                        echo "composer.lock found in vulnerabilities/api"
                    else
                        echo "WARNING: composer.lock missing!"
                    fi
                    '''
                }
            }
        }

        stage('Build / Prepare App') {
            steps {
                dir('vulnerabilities/api') {
                    docker.image('composer:latest').inside {
                        sh '''
                        composer install --no-interaction --no-progress --no-suggest --prefer-dist
                        '''
                    }
                }
            }
        }

        stage('Code Quality') {
            steps {
                dir('vulnerabilities/api') {
                    docker.image('sonarsource/sonar-scanner-cli:latest').inside {
                        withSonarQubeEnv('SonarQube') {
                            sh '''
                            if [ -f sonar-project.properties ]; then
                                sonar-scanner
                            elif command -v phpstan > /dev/null; then
                                phpstan analyse . || exit 1
                            elif command -v phpcs > /dev/null; then
                                phpcs . || exit 1
                            else
                                echo "No code analysis tools found!"
                                exit 1
                            fi
                            '''
                        }
                    }
                }
            }
        }

        stage('SAST') {
            steps {
                docker.image('returntocorp/semgrep').inside {
                    sh 'semgrep --config=auto vulnerabilities/api --output semgrep-report.sarif || exit 1'
                    archiveArtifacts artifacts: 'semgrep-report.sarif', allowEmptyArchive: true
                }
            }
        }

        stage('SCA') {
            steps {
                docker.image('aquasec/trivy:latest').inside {
                    sh '''
                    if [ -f vulnerabilities/api/composer.lock ]; then
                        trivy fs vulnerabilities/api --severity CRITICAL --exit-code 1 || exit 1
                    else
                        echo "composer.lock missing, skipping SCA"
                    fi
                    '''
                    archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                docker.image('docker:latest').inside('-v /var/run/docker.sock:/var/run/docker.sock') {
                    sh """
                    docker build --no-cache --pull \
                        --label commit=${env.GIT_COMMIT} \
                        --label branch=${env.BRANCH_NAME} \
                        --label build_url=${env.BUILD_URL} \
                        -t ${DOCKER_IMAGE} \
                        -t ${DOCKER_IMAGE_BRANCH} .
                    """
                }
            }
        }

        stage('Image Scan') {
            steps {
                docker.image('aquasec/trivy:latest').inside('-v /var/run/docker.sock:/var/run/docker.sock') {
                    sh "trivy image --severity CRITICAL --exit-code 1 ${DOCKER_IMAGE}"
                }
            }
        }

        stage('Push Image') {
            steps {
                docker.image('docker:latest').inside('-v /var/run/docker.sock:/var/run/docker.sock') {
                    sh """
                    docker tag ${DOCKER_IMAGE} ${LOCAL_REGISTRY}/${DOCKER_IMAGE}
                    docker tag ${DOCKER_IMAGE_BRANCH} ${LOCAL_REGISTRY}/${DOCKER_IMAGE_BRANCH}
                    docker push ${LOCAL_REGISTRY}/${DOCKER_IMAGE}
                    docker push ${LOCAL_REGISTRY}/${DOCKER_IMAGE_BRANCH}
                    """
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
                docker.image('docker/compose:latest').inside('-v /var/run/docker.sock:/var/run/docker.sock') {
                    script {
                        if (env.BRANCH_NAME == 'prod') {
                            input message: "Manual approval required for PROD deployment"
                        }
                    }
                    sh """
                    docker network create ${DEPLOY_NETWORK} || true
                    docker-compose -f docker-compose-${BRANCH_NAME}.yml up -d
                    """
                }
            }
        }

        stage('DAST') {
            steps {
                docker.image('owasp/zap2docker-stable').inside {
                    script {
                        if (env.BRANCH_NAME == 'dev') {
                            sh """
                            zap-baseline.py -t http://localhost:${DEPLOY_PORT} -g gen.conf -r zap_report.html || exit 1
                            """
                        } else if (env.BRANCH_NAME == 'prod') {
                            sh """
                            zap-baseline.py -t http://localhost:${DEPLOY_PORT} -g gen.conf -r zap_report.html -J -w 2
                            """
                        }
                    }
                    archiveArtifacts artifacts: 'zap_report.html', allowEmptyArchive: true
                }
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
                // Add other report publishers as needed
            }
        }
    }

    post {
        always {
            docker.image('docker/compose:latest').inside('-v /var/run/docker.sock:/var/run/docker.sock') {
                sh 'docker-compose down || true'
            }
        }
        success {
            echo "Pipeline completed successfully!"
        }
        failure {
            echo "Pipeline failed. Please check logs and reports."
        }
    }
}
