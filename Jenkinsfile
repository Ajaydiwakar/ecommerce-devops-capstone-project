pipeline {
    agent { label 'linux-builder' } // The slave node

    environment {
        BUILD_NUMBER = "${env.BUILD_ID}"
        ECR_REGISTRY = "123456789012.dkr.ecr.us-east-1.amazonaws.com"
        IMAGE_NAME = "ecommerce"
    }

    stages {
        stage('Build & Unit Test') {
            steps {
                // mvn test triggers Surefire + JaCoCo (prepare-agent & report)
                sh 'mvn clean test'
            }
        }
        
        stage('Code Quality') {
            steps {
                // Fails the build if coverage drops below the gate
                withCredentials([string(credentialsId: 'sonar-token', variable: 'SONAR_TOKEN')]) {
                    sh '''
                    mvn sonar:sonar \
                      -Dsonar.host.url=https://sonar.internal:9000 \
                      -Dsonar.login=$SONAR_TOKEN \
                      -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
                    '''
                }
            }
        }
        
        stage('Build Image') {
            steps {
                // Package the jar and build the Docker image
                sh 'mvn package -DskipTests'
                sh "docker build -t ${ECR_REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER} ."
            }
        }
        
        stage('Scan Image') {
            steps {
                // Trivy scans the local image before pushing. HIGH/CRITICAL = fail
                sh "trivy image --exit-code 1 --severity HIGH,CRITICAL ${ECR_REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
            }
        }
        
        stage('Push Image') {
            steps {
                // Push immutable artifact to ECR
                sh "aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${ECR_REGISTRY}"
                sh "docker push ${ECR_REGISTRY}/${IMAGE_NAME}:${BUILD_NUMBER}"
            }
        }
        
        stage('Deploy') {
            steps {
                // Jenkins acts as orchestrator, Ansible does the deployment work
                sshagent(['ansible-ssh-key']) {
                    sh "ssh -o StrictHostKeyChecking=no ec2-user@ansible-server 'ansible-playbook /path/to/deploy.yml -e build_number=${BUILD_NUMBER}'"
                }
            }
        }
    }
}