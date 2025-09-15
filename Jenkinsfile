pipeline {
    agent any

    triggers {
        pollSCM('H/15 * * * *')
        cron('H 0 * * *')
    }

    environment {
        REGISTRY_URL = '192.168.146.133:5000'
        DOCKER_CREDENTIALS_ID = 'dockerRegistry'
        DEPLOY_PORT = '8081'
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
                    sh 'curl -o trivy-html.tpl https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/html.tpl'
                    sh """
                        cd $WORKSPACE/vulnerabilities/api
                        composer install --no-interaction --no-progress --prefer-dist
                        pwd
                        docker run --rm -v $WORKSPACE/vulnerabilities/api:/src -w /src returntocorp/semgrep semgrep scan --config=auto . --json --output=semgrep-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.sarif
                    """
                    archiveArtifacts "vulnerabilities/api/semgrep-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.sarif"
                    
                }
            }
        }

        stage('Publish SARIF Report') {
            steps {
                recordIssues(
                    enabledForFailure: true,
                    publishAllIssues: true,
                    tool: sarif(pattern: "vulnerabilities/api/semgrep-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.sarif")
                )
            }
        }

        stage('SonarQube Analysis') {
            environment {
                SCANNER_HOME = tool 'SonarQubeScanner'  // must match Jenkins Global Tool Configuration
            }
            steps {
                withSonarQubeEnv('SonarQubeScanner') {  // must match SonarQube server config name in Jenkins
                    sh """
                        $SCANNER_HOME/bin/sonar-scanner \
                        -Dsonar.sources=vulnerabilities/api \
                        -Dsonar.projectName='DVWA-${env.BRANCH_NAME}' \
                        -Dsonar.projectKey=DVWA-${env.BRANCH_NAME} \
                        -Dsonar.host.url=${env.SONAR_HOST_URL} \
                    """
                }
            }
        }

        stage('Trivy Scan') {
            steps {
                script {
                    if (fileExists('vulnerabilities/api/composer.lock')) {
                        // JSON report
                        sh """
                            trivy fs . --skip-version-check --severity CRITICAL --format json --output trivy-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.json
                        """
                        // HTML report
                        sh """
                            trivy fs . --skip-version-check --severity CRITICAL --format template --template "@trivy-html.tpl" --output trivy-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.html
                        """
                    } else {
                        echo "Skipping SCA scan: composer.lock not found"
                    }
                }
                archiveArtifacts artifacts: "trivy-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.json, trivy-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.html", allowEmptyArchive: true
            }
        }

        stage('Publish Trivy FS Reports') {
            steps {
                recordIssues(
                    enabledForFailure: true,
                    publishAllIssues: true,
                    tool: trivy(pattern: "trivy-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.json", id: 'trivy-fs')
                )
                publishHTML([
                    reportDir: '.',
                    reportFiles: "trivy-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.html",
                    reportName: 'Trivy FS Report',
                    keepAll: true,
                    alwaysLinkToLastBuild: true,
                    allowMissing: true
                ])
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
                    }
                }
            }
        }

        stage('Trivy Image Scan') {
            steps {
                script {
                    // JSON report
                    sh """
                        trivy image --skip-version-check --severity CRITICAL -f json -o trivy-image-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.json ${env.IMAGE_NAME}
                    """
                    // HTML report
                    sh """
                        trivy image --skip-version-check --severity CRITICAL --format template --template "@trivy-html.tpl" -o trivy-image-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.html ${env.IMAGE_NAME}
                    """
                }
                archiveArtifacts artifacts: "trivy-image-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.json, trivy-image-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.html", allowEmptyArchive: true
            }
        }

        stage ('Docker Push') {
            steps {
                script {
                    docker.withRegistry("http://${env.REGISTRY_URL}", env.DOCKER_CREDENTIALS_ID) {
                        sh "docker push ${env.IMAGE_NAME}"
                        sh "docker push ${env.IMAGE_NAME_BRANCH}"
                    }
                }
            }
        }

        stage('Publish Docker Image Reports') {
            steps {
                recordIssues(
                    enabledForFailure: true,
                    publishAllIssues: true,
                    tool: trivy(pattern: "trivy-image-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.json", id: 'trivy-image')
                )
                publishHTML([
                    reportDir: '.',
                    reportFiles: "trivy-image-report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.html",
                    reportName: 'Trivy Image Report',
                    keepAll: true,
                    alwaysLinkToLastBuild: true,
                    allowMissing: true
                ])
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
                        sleep 20
                        docker-compose logs --tail=100
                    """
                }
            }
        }

        stage('Health Check') {
            steps {
                script {
                    // Use the same Docker network your service runs on
                    def network = env.DEPLOY_NETWORK // e.g., 'uat_net' or 'prod_net'
                    // Target service details
                    def targetHost = 'dvwa'       // service or container name
                    def targetPort = '80'          // internal container port

                    sh """
                        docker run --rm --network ${network} curlimages/curl:latest -s -o /dev/null -w '%{http_code}' http://${targetHost} || exit 1
                    """
                }
            }
        }

        stage('DAST with ZAP') {
            steps {
                script {
                    def targetHost = 'dvwa'
                    def targetPort = env.DEPLOY_PORT ?: '8081'
                    def targetUrl = "http://${targetHost}"

                    // Run ZAP baseline scan with authentication; adjust command per your ZAP auth method
                    sh """
                    mkdir -p zap-work
                    chmod 777 zap-work
                    docker run --rm -v \$PWD/zap-work:/zap/wrk --network ${env.DEPLOY_NETWORK} -t ghcr.io/zaproxy/zaproxy:stable \
                        zap-baseline.py -t ${targetUrl} -r zap_report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.html \
                        -J zap_report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.json -w zap_report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.md -x zap_report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.xml 2 || true
                    """
                }
                archiveArtifacts artifacts: "zap-work/zap_report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.html,zap-work/zap_report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.json,zap-work/zap_report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.md,zap-work/zap_report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.xml", allowEmptyArchive: true
            }
        }

        stage('Publish ZAP Reports') {
            steps {
                publishHTML([
                    reportDir: 'zap-work',
                    reportFiles: "zap_report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.html",
                    reportName: 'ZAP Report',
                    keepAll: true,
                    alwaysLinkToLastBuild: true,
                    allowMissing: true
                ])
                junit allowEmptyResults: true, testResults: "zap-work/zap_report-${env.BRANCH_NAME}-${env.BUILD_NUMBER}.xml"
            }
        }
    }

    post {
        always {
            script {
                sh """
                    echo "Cleaning up resources..."
                    trivy clean --all || true
                    docker-compose down || true
                    docker volume rm ${env.DEPLOY_VOLUME} -f || true
                    docker network rm ${env.DEPLOY_NETWORK} -f || true
                    docker rmi ${env.IMAGE_NAME} ${env.IMAGE_NAME_BRANCH} || true
                    docker system prune -f || true
                """
                cleanWs()
            }
        }
        success { echo "Pipeline completed successfully" }
        failure { echo "Pipeline failed. Check logs." }
    }
}
