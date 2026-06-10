pipeline {
    agent { label '' }

    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        TF_DIR             = 'terraform'
    }

    parameters {
        choice(
            name: 'ACTION',
            choices: ['plan', 'apply', 'destroy'],
            description: 'Action Terraform à exécuter'
        )
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'aws-session-token',     variable: 'AWS_SESSION_TOKEN')
                ]) {
                    dir(env.TF_DIR) {
                        sh 'terraform init -reconfigure'
                    }
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'aws-session-token',     variable: 'AWS_SESSION_TOKEN')
                ]) {
                    dir(env.TF_DIR) {
                        sh 'terraform validate'
                    }
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'aws-session-token',     variable: 'AWS_SESSION_TOKEN')
                ]) {
                    dir(env.TF_DIR) {
                        sh 'terraform plan -out=tfplan'
                    }
                }
            }
        }

        stage('Approval') {
            when {
                expression { params.ACTION in ['apply', 'destroy'] }
            }
            steps {
                input message: "Confirmer l'action : ${params.ACTION} ?", ok: 'Continuer'
            }
        }

        stage('Terraform Apply / Destroy') {
            when {
                expression { params.ACTION in ['apply', 'destroy'] }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'aws-session-token',     variable: 'AWS_SESSION_TOKEN')
                ]) {
                    dir(env.TF_DIR) {
                        script {
                            if (params.ACTION == 'apply') {
                                sh 'terraform apply -auto-approve tfplan'
                            } else {
                                sh 'terraform destroy -auto-approve'
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        success { echo "Pipeline terminé avec succès." }
        failure { echo "Échec du pipeline." }
    }
}
