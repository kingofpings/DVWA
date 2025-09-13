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
                        docker run --rm -v $PWD:/src -w /src returntocorp/semgrep semgrep --config=auto . --json --output=semgrep-report.sarif

                    '''
                    archiveArtifacts 'vulnerabilities/api/semgrep-report.sarif'
                }
            }
        }
        stage('Publish SARIF Report') {
        steps {
                recordIssues(
                    enabledForFailure: true,
                    publishAllIssues: true,
                    tool: sarif(pattern: 'vulnerabilities/api/semgrep-report.sarif')
                )
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
                        // JSON report
                        sh '''
                            docker run --rm -v $PWD:/project -w /project aquasec/trivy fs . \
                            --severity CRITICAL --format json --output trivy-report.json || true
                        '''
                        // HTML report
                        sh '''
                            docker run --rm -v $PWD:/project -w /project aquasec/trivy fs . \
                            --severity CRITICAL --format template --template "@/contrib/html.tpl" --output trivy-report.html || true
                        '''
                    } else {
                        echo "Skipping SCA scan: composer.lock not found"
                    }
                }
                archiveArtifacts artifacts: 'trivy-report.json,trivy-report.html', allowEmptyArchive: true
            }
        }

        stage('Publish Trivy JSON Report') {
            steps {
                recordIssues(
                    enabledForFailure: true,
                    publishAllIssues: true,
                    tool: trivy(pattern: 'trivy-report.json')
                )
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
                        sh 'pwd'
                        sh 'ls -ltr'
                        // JSON report
                        sh """
                            docker run --rm -v /var/run/docker.sock:/var/run/docker.sock  \
                            aquasec/trivy image --severity CRITICAL -f json -o trivy-image-report.json ${env.IMAGE_NAME} || true
                        """
                        // HTML report
                        sh """
                            docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                            aquasec/trivy image --severity CRITICAL --format template --template "@contrib/html.tpl" -o trivy-image-report.html ${env.IMAGE_NAME} || true
                        """
                        sh 'ls -ltr'
                        sh "docker push ${env.IMAGE_NAME}"
                        sh "docker push ${env.IMAGE_NAME_BRANCH}"
                    }
                }
                archiveArtifacts artifacts: 'trivy-image-report.json,trivy-image-report.html', allowEmptyArchive: true
            }
        }

        stage('Publish Docker Image Reports') {
            steps {
                publishHTML([
                    reportDir: '.',
                    reportFiles: 'trivy-image-report.html',
                    reportName: 'Trivy Image Report',
                    keepAll: true,
                    alwaysLinkToLastBuild: false,
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
                    def network = env.DEPLOY_NETWORK ?: 'uat_net'
                    def targetHost = 'dvwa'       // service or container name
                    def targetPort = '80'          // internal container port

                    sh """
                        docker run --rm --network ${network} curlimages/curl:latest -s -o /dev/null -w '%{http_code}' http://${targetHost} || exit 1
                    """
                }
            }
        }

        // stage('DVWA Setup Authenticated') {
        //     steps {
        //         withCredentials([usernamePassword(credentialsId: 'DVWA_SETUP_CREDENTIALS', usernameVariable: 'DVWA_USER', passwordVariable: 'DVWA_PASS')]) {
        //             script {
        //                 def targetHost = 'dvwa'
        //                 def targetPort = env.DEPLOY_PORT ?: '8081'
        //                 def loginUrl = "http://${targetHost}/login.php"
        //                 def setupUrl = "http://${targetHost}/setup.php"

        //                 sh """
        //                 docker run --rm --network ${env.DEPLOY_NETWORK} curlimages/curl:latest \\
        //                     --location --cookie-jar dvwa_cookie.txt --output login.html --silent "${loginUrl}"

        //                 CSRF=\$(grep 'user_token' login.html | sed -n 's/.*value="\\(.*\\)".*/\\1/p')

        //                 docker run --rm --network ${env.DEPLOY_NETWORK} curlimages/curl:latest \\
        //                     --location --cookie dvwa_cookie.txt --cookie-jar dvwa_cookie.txt \\
        //                     --data "username=$DVWA_USER&password=$DVWA_PASS&Login=Login&user_token=\${CSRF}" --output login2.html --silent "${loginUrl}"

        //                 docker run --rm --network ${env.DEPLOY_NETWORK} curlimages/curl:latest \\
        //                     --location --cookie dvwa_cookie.txt --output setup.html --silent "${setupUrl}"
        //                 """
        //             }
        //         }
        //     }
        // }

        stage('DAST with ZAP') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'DVWA_CREDENTIALS', usernameVariable: 'DVWA_USER', passwordVariable: 'DVWA_PASS')]) {
                script {
                    def targetHost = 'dvwa'
                    def targetPort = env.DEPLOY_PORT ?: '8081'
                    def targetUrl = "http://${targetHost}"

                    // Run ZAP baseline scan with authentication; adjust command per your ZAP auth method
                    sh """
                    mkdir -p zap-work
                    chmod 777 zap-work
                    docker run --rm -v \$PWD/zap-work:/zap/wrk --network ${env.DEPLOY_NETWORK} -t ghcr.io/zaproxy/zaproxy:stable \
                        zap-baseline.py -t ${targetUrl} -g gen.conf -r zap_report.html \
                        -J zap_report.json -w zap_report.md -x zap_report.xml 2 || true
                    """
                }
                }
                archiveArtifacts artifacts: 'zap-work/zap_report.html,zap-work/zap_report.json,zap-work/zap_report.md,zap-work/zap_report.xml', allowEmptyArchive: true
            }
        }



        // stage('DAST') {
        //     steps {
        //         script {
        //             def targetHost = 'dvwa'  // Docker service/container name reachable on the deploy network
        //             def targetUrl = "http://${targetHost}:${env.DEPLOY_PORT}"
        //             def zapCmd = env.BRANCH_NAME == 'prod' ?
        //                 "docker run --rm -v \$PWD:/zap/wrk --network ${env.DEPLOY_NETWORK} -t ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t ${targetUrl} -g gen.conf -r zap_report.html -J -w 2" :
        //                 "docker run --rm -v \$PWD:/zap/wrk --network ${env.DEPLOY_NETWORK} -t ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t ${targetUrl} -g gen.conf -r zap_report.html || exit 1"
        //             sh zapCmd
        //         }
        //         archiveArtifacts artifacts: 'zap_report.html', allowEmptyArchive: true
        //     }
        // }

        stage('Publish ZAP Reports') {
            steps {
                publishHTML([
                    reportDir: 'zap-work',
                    reportFiles: 'zap_report.html',
                    reportName: 'ZAP Report',
                    keepAll: true,
                    alwaysLinkToLastBuild: false,
                    allowMissing: true
                ])
                junit allowEmptyResults: true, testResults: 'zap_report.xml'
            }
        }
    }

    post {
        always {
            script {
                sh 'docker-compose down || true'
                sh 'docker network rm ${env.DEPLOY_NETWORK} -f || true'
                sh 'docker image rm ${env.IMAGE_NAME} ${env.IMAGE_NAME_BRANCH} || true'
                sh 'docker system prune -f || true'
                sh 'docker volume rm ${env.DEPLOY_VOLUME} -f || true'
                cleanWs()
            }
        }
        success { echo "Pipeline completed successfully" }
        failure { echo "Pipeline failed. Check logs." }
    }
}
