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

                        semgrep --config=auto . --output semgrep-report.sarif
                    '''
                    archiveArtifacts 'vulnerabilities/api/semgrep-report.sarif'
                }
            }
        }

        stage('SonarQube Analysis') {
            environment {
                SCANNER_HOME = tool 'SonarQubeScanner'  // must match Jenkins Global Tool Configuration
            }
            steps {
                withSonarQubeEnv('SonarQubeScanner') {  // must match SonarQube server config name in Jenkins
                    sh '''
                        $SCANNER_HOME/bin/sonar-scanner \
                        -Dsonar.sources=vulnerabilities/api
                    '''
                }
            }
        }

        stage('Trivy Scan') {
            steps {
                script {
                    if (fileExists('vulnerabilities/api/composer.lock')) {
                        sh 'trivy fs vulnerabilities/api --severity CRITICAL --exit-code 1 || true'
                    } else {
                        echo "Skipping SCA scan: composer.lock not found"
                    }
                }
                archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
            }
        }

        stage('Docker Build and Push') {
            steps {
                script {
                    docker.withRegistry("http://${env.REGISTRY_URL}", env.DOCKER_CREDENTIALS_ID) {
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

        stage('Health Check') {
            steps {
                script {
                    // Use the same Docker network your service runs on
                    def network = env.DEPLOY_NETWORK ?: 'uat_net'
                    def targetHost = 'dvwa'       // service or container name
                    def targetPort = '80'          // internal container port

                    sh """
                        docker run --rm --network ${network} curlimages/curl:latest -s -o /dev/null -w '%{http_code}' http://${targetHost}:${targetPort}/health || exit 1
                    """
                }
            }
        }

        stage('DAST') {
            steps {
                script {
                    def targetHost = 'dvwa'  // Docker service/container name reachable on the deploy network
                    def targetUrl = "http://${targetHost}:${env.DEPLOY_PORT}"
                    def zapCmd = env.BRANCH_NAME == 'prod' ?
                        "docker run --rm -v \$PWD:/zap/wrk --network ${env.DEPLOY_NETWORK} -t zaproxy/zap-stable zap-baseline.py -t ${targetUrl} -g gen.conf -r zap_report.html -J -w 2" :
                        "docker run --rm -v \$PWD:/zap/wrk --network ${env.DEPLOY_NETWORK} -t zaproxy/zap-stable zap-baseline.py -t ${targetUrl} -g gen.conf -r zap_report.html || exit 1"
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
                sh 'docker network rm ${env.DEPLOY_NETWORK} -f || true'
            }
        }
        success { echo "Pipeline completed successfully" }
        failure { echo "Pipeline failed. Check logs." }
    }
}
