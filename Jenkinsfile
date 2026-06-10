pipeline {
    agent any

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
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-vocareum-creds'
                ]]) {
                    dir(env.TF_DIR) {
                        sh 'terraform init -reconfigure'
                    }
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                dir(env.TF_DIR) {
                    sh 'terraform validate'
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-vocareum-creds'
                ]]) {
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
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'aws-vocareum-creds'
                ]]) {
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
