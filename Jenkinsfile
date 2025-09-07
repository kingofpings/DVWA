pipeline {
    agent any

    environment {
        REGISTRY_URL = '192.168.146.133:5000'
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

        stage('Checkout Source') {
            steps {
                checkout scm
            }
        }

        stage('Build and Scan') {
            steps {
                script {
                    sh '''
                        cd vulnerabilities/api
                        composer install --no-interaction --no-progress --prefer-dist

                        if [ -f sonar-project.properties ]; then
                            sonar-scanner
                        elif command -v /home/jenkins/.composer/vendor/bin/phpstan >/dev/null 2>&1; then
                            /home/jenkins/.composer/vendor/bin/phpstan analyse .
                        elif command -v phpcs >/dev/null 2>&1; then
                            /home/jenkins/.composer/vendor/bin/phpcs .
                        else
                            echo "No code quality tool found"
                            exit 1
                        fi

                        semgrep --config=auto vulnerabilities/api --output semgrep-report.sarif
                    '''
                    archiveArtifacts 'semgrep-report.sarif'

                    script {
                        if (fileExists('vulnerabilities/api/composer.lock')) {
                            sh 'trivy fs vulnerabilities/api --severity CRITICAL --exit-code 1 || true'
                        } else {
                            echo "Skipping SCA scan: composer.lock not found"
                        }
                    }
                    archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true

                    docker.withRegistry("http://${env.REGISTRY_URL}", env.DOCKER_CREDENTIALS_ID) {
                        echo "Logged into Docker registry ${env.REGISTRY_URL}"
                        sh """
                            docker build --no-cache --pull \
                                --label commit=${env.GIT_COMMIT} \
                                --label branch=${env.BRANCH_NAME} \
                                --label build_url=${env.BUILD_URL} \
                                -t ${env.IMAGE_NAME} \
                                -t ${env.IMAGE_NAME_BRANCH} .
                        """
                        sh "trivy image --severity CRITICAL --exit-code 1 ${env.IMAGE_NAME} || true"

                        sh "docker push ${env.IMAGE_NAME}"
                        sh "docker push ${env.IMAGE_NAME_BRANCH}"
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
                        docker network create ${env.DEPLOY_NETWORK} || true
                        docker-compose -f docker-compose-${env.BRANCH_NAME}.yml up -d
                    """
                }
            }
        }

        stage('DAST') {
            steps {
                script {
                    def zapCmd = env.BRANCH_NAME == 'prod' ?
                        "docker run --rm -v \$PWD:/zap/wrk -t owasp/zap2docker-stable zap-baseline.py -t http://localhost:${env.DEPLOY_PORT} -g gen.conf -r zap_report.html -J -w 2" :
                        "docker run --rm -v \$PWD:/zap/wrk -t owasp/zap2docker-stable zap-baseline.py -t http://localhost:${env.DEPLOY_PORT} -g gen.conf -r zap_report.html || exit 1"
                    sh zapCmd
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
                sh 'docker-compose down || true'
            }
        }
        success { echo "Pipeline completed successfully" }
        failure { echo "Pipeline failed. Check logs." }
    }
}
