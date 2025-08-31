pipeline {
    agent {
        docker {
            image 'localhost:5000/jenkins-agent-dvwa:latest'  // Replace with your custom Jenkins agent image
            args '-v /var/run/docker.sock:/var/run/docker.sock --privileged'
        }
    }

    parameters {
        string(name: 'REGISTRY_URL', defaultValue: 'localhost:5000', description: 'Docker Registry URL')
        string(name: 'REGISTRY_CREDENTIALS_ID', defaultValue: 'dockerRegistry', description: 'Jenkins Credentials ID for Docker Registry')
    }

    environment {
        DOCKER_IMAGE = "dvwa:${env.GIT_COMMIT}"
        DOCKER_IMAGE_BRANCH = "dvwa:${env.BRANCH_NAME}"
        LOCAL_REGISTRY = "${params.REGISTRY_URL}"
        DEPLOY_PORT = '8081'    // default, overridden below
        DEPLOY_NETWORK = 'uat_net' // default, overridden below
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        skipDefaultCheckout()
    }

    stages {
        stage('Set Environment Variables') {
            steps {
                script {
                    if (env.BRANCH_NAME == 'prod') {
                        env.DEPLOY_PORT = '8082'
                        env.DEPLOY_NETWORK = 'prod_net'
                    } else {
                        env.DEPLOY_PORT = '8081'
                        env.DEPLOY_NETWORK = 'uat_net'
                    }
                }
            }
        }

        stage('Checkout Source') {
            steps {
                checkout scm
                sh '''
                if [ -f vulnerabilities/api/composer.lock ]; then
                    echo "composer.lock found in vulnerabilities/api"
                else
                    echo "Warning: composer.lock missing!"
                fi
                '''
            }
        }

        stage('Build / Prepare App') {
            steps {
                dir('vulnerabilities/api') {
                    sh 'composer install --no-interaction --no-progress --no-suggest --prefer-dist'
                }
            }
        }

        stage('Code Quality') {
            steps {
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
            }
        }

        stage('SAST') {
            steps {
                sh 'semgrep --config=auto vulnerabilities/api --output semgrep-report.sarif'
                archiveArtifacts artifacts: 'semgrep-report.sarif'
            }
        }

        stage('SCA') {
            steps {
                script {
                    if (fileExists('vulnerabilities/api/composer.lock')) {
                        sh 'trivy fs vulnerabilities/api --severity CRITICAL --exit-code 1'
                    } else {
                        echo "Skipping SCA scan: composer.lock not found"
                    }
                }
                archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
            }
        }

        stage('Docker Login') {
            steps {
                script {
                    docker.withRegistry("http://${params.REGISTRY_URL}", params.REGISTRY_CREDENTIALS_ID) {
                        echo "Logged into Docker registry ${params.REGISTRY_URL}"
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
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

        stage('Image Scan') {
            steps {
                sh "trivy image --severity CRITICAL --exit-code 1 ${DOCKER_IMAGE}"
            }
        }

        stage('Push Docker Image') {
            steps {
                script {
                    docker.withRegistry("http://${params.REGISTRY_URL}", params.REGISTRY_CREDENTIALS_ID) {
                        sh """
                        docker tag ${DOCKER_IMAGE} ${LOCAL_REGISTRY}/${DOCKER_IMAGE}
                        docker tag ${DOCKER_IMAGE_BRANCH} ${LOCAL_REGISTRY}/${DOCKER_IMAGE_BRANCH}
                        docker push ${LOCAL_REGISTRY}/${DOCKER_IMAGE}
                        docker push ${LOCAL_REGISTRY}/${DOCKER_IMAGE_BRANCH}
                        """
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
                        input message: "Manual approval required for PROD deployment"
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
                script {
                    if (env.BRANCH_NAME == 'dev') {
                        sh """
                        docker run --rm -v \$PWD:/zap/wrk -t owasp/zap2docker-stable zap-baseline.py \
                          -t http://localhost:${DEPLOY_PORT} -g gen.conf -r zap_report.html || exit 1
                        """
                    } else if (env.BRANCH_NAME == 'prod') {
                        sh """
                        docker run --rm -v \$PWD:/zap/wrk -t owasp/zap2docker-stable zap-baseline.py \
                          -t http://localhost:${DEPLOY_PORT} -g gen.conf -r zap_report.html -J -w 2
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
            sh 'docker-compose down || true'
        }
        success {
            echo "Pipeline completed successfully!"
        }
        failure {
            echo "Pipeline failed! Please check logs and reports."
        }
    }
}
