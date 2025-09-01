pipeline {
    agent any

    environment {
        REGISTRY_URL = 'localhost:5000'
        DOCKER_CREDENTIALS_ID = 'dockerRegistry'
        DEPLOY_PORT = '8081'
        DEPLOY_NETWORK = 'uat_net'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
    }

    stages {
        stage('Initialize') {
            steps {
                ws("/home/jenkins/workspace/${env.BRANCH_NAME}") {
                    script {
                        if (env.BRANCH_NAME == 'prod') {
                            env.DEPLOY_PORT = '8082'
                            env.DEPLOY_NETWORK = 'prod_net'
                        } else {
                            env.DEPLOY_PORT = '8081'
                            env.DEPLOY_NETWORK = 'uat_net'
                        }

                        def commit = env.GIT_COMMIT ?: 'latest'
                        env.IMAGE_NAME = "${env.REGISTRY_URL}/dvwa:${commit}"
                        env.IMAGE_NAME_BRANCH = "${env.REGISTRY_URL}/dvwa:${env.BRANCH_NAME}"
                    }
                }
            }
        }

        stage('Checkout Source') {
            steps {
                ws("/home/jenkins/workspace/${env.BRANCH_NAME}") {
                    checkout scm
                }
            }
        }

        stage('Build and Scan in Docker') {
            steps {
                ws("/home/jenkins/workspace/${env.BRANCH_NAME}") {
                    script {
                        docker.image("${env.REGISTRY_URL}/jenkins-agent-dvwa:latest")
                            .inside('-u jenkins --privileged -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/jenkins:/var/lib/jenkins:rw') {

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

                                docker.withRegistry("http://${env.REGISTRY_URL}", env.DOCKER_CREDENTIALS_ID) {
                                    echo "Logged into Docker registry ${env.REGISTRY_URL}"
                                }

                                sh """
                                    docker build --no-cache --pull \
                                    --label commit=${env.GIT_COMMIT} \
                                    --label branch=${env.BRANCH_NAME} \
                                    --label build_url=${env.BUILD_URL} \
                                    -t ${env.IMAGE_NAME} \
                                    -t ${env.IMAGE_NAME_BRANCH} .
                                """

                                sh "trivy image --severity CRITICAL --exit-code 1 ${env.IMAGE_NAME}"

                                docker.withRegistry("http://${env.REGISTRY_URL}", env.DOCKER_CREDENTIALS_ID) {
                                    sh "docker push ${env.IMAGE_NAME}"
                                    sh "docker push ${env.IMAGE_NAME_BRANCH}"
                                }
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
                ws("/home/jenkins/workspace/${env.BRANCH_NAME}") {
                    script {
                        if (env.BRANCH_NAME == 'prod') {
                            input message: "Approve PROD deployment"
                        }
                        sh """
                            docker network create ${env.DEPLOY_NETWORK} || true
                            docker-compose -f docker-compose-${env.BRANCH_NAME}.yml up -d
                        """
                    }
                }
            }
        }

        stage('DAST') {
            steps {
                ws("/home/jenkins/workspace/${env.BRANCH_NAME}") {
                    script {
                        def zapCmd = env.BRANCH_NAME == 'prod' ?
                                "docker run --rm -v \$PWD:/zap/wrk -t owasp/zap2docker-stable zap-baseline.py -t http://localhost:${env.DEPLOY_PORT} -g gen.conf -r zap_report.html -J -w 2" :
                                "docker run --rm -v \$PWD:/zap/wrk -t owasp/zap2docker-stable zap-baseline.py -t http://localhost:${env.DEPLOY_PORT} -g gen.conf -r zap_report.html || exit 1"
                        sh zapCmd
                    }
                    archiveArtifacts artifacts: 'zap_report.html', allowEmptyArchive: true
                }
            }
        }

        stage('Publish Reports') {
            steps {
                ws("/home/jenkins/workspace/${env.BRANCH_NAME}") {
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
    }

    post {
        always {
            script {
                node {
                    sh 'docker-compose down || true'
                }
            }
        }
        success { echo "Pipeline completed successfully" }
        failure { echo "Pipeline failed. Check logs." }
    }
}
