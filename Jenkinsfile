//Define variables
def scmVars

//Start Pipeline
pipeline {
    
  //Configure Jenkins Slave
  agent {
    //Use Kubernetes as dynamic Jenkins Slave
    kubernetes {
      //Kubernetes Manifest File to spin up Pod to do build
      yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: docker
    image: docker:20.10.3-dind
    command:
    - dockerd
    - --host=unix:///var/run/docker.sock
    - --host=tcp://0.0.0.0:2375
    - --storage-driver=overlay2
    tty: true
    securityContext:
      privileged: true
  - name: helm
    image: lachlanevenson/k8s-helm:v3.5.0
    command:
    - cat
    tty: true
  - name: skan
    image: alcide/skan:v0.9.0-debug
    command:
    - cat
    tty: true
  - name: trivy
    image: aquasec/trivy
    command:
    - cat
    tty: true
  - name: java-node
    image: timbru31/java-node:11-alpine-jre-14
    command:
    - cat
    tty: true
    volumeMounts:
    - mountPath: /home/jenkins/dependency-check-data
      name: dependency-check-data
  volumes:
  - name: dependency-check-data
    hostPath:
      path: /tmp/dependency-check-data
"""
    }//End kubernetes
  }//End agent
  
    environment {
        ENV_NAME = "${BRANCH_NAME == "master" ? "uat" : "${BRANCH_NAME}"}"
        SCANNER_HOME = tool 'sonarqube-scanner'
        PROJECT_KEY = "vue-sample-app"
        PROJECT_NAME = "vue-sample-app"
    }
  
    //Start Pipeline
    stages {
        // ***** Stage Clone *****
        stage('Clone vue-app source code') {
            // Steps to run build
            steps {
            // Run in Jenkins Slave container
            container('jnlp') {
                //Use script to run
                script {
                    
                    security {
                        gitHostKeyVerificationConfiguration {
                        sshHostKeyVerificationStrategy('knownHostsFileVerificationStrategy')
                        }
                    }
                // Git clone repo and checkout branch as we put in parameter
                scmVars = git branch: "${BRANCH_NAME}",
                                credentialsId: 'opsta-bootcamp-git-deploy-key',
                                url: 'git@gitlab.com:bookinfo-workshop/ratings.git'
                }// End Script
            }// End Container
            }// End steps
        }//End stage

        // ***** Stage sKan ******
        stage('sKan') {
            steps {
                container('helm') {
                    script {
                        //Generate k8s-manifest-deploy.yaml for scanning
                        sh "helm template -f k8s/helm-values/values-bookinfo-${ENV_NAME}-ratings.yaml \
                            --set extraEnv.COMMIT_ID=${scmVars.GIT_COMMIT} \
                            --namespace ais-bookinfo-${ENV_NAME} bookinfo-${ENV_NAME}-ratings k8s/helm \
                            > k8s-manifest-deploy.yaml"
                    } // End script
                } // End container
                container('skan') {
                    script {
                        // Scanning with sKan
                        sh "/skan manifest -f k8s-manifest-deploy.yaml"
                        // Keep report as artifacts
                        archiveArtifacts artifacts: 'skan-result.html'
                        sh "rm k8s-manifest-deploy.yaml"
                    } // End script
                } // End container
            } // End steps
        } // End stage

        // ***** Stage Sonarqube *****
        stage('Sonarqube Scanner') {
            steps {
                container('java-node') {
                    script {
                        withSonarQubeEnv('sonarqube-jenkins') {
                            sh '''
                            ${SCANNER_HOME}/bin/sonar-scanner \
                            -D sonar.projectKey=${PROJECT_KEY} \
                            -D sonar.projectName=${PROJECT_NAME} \
                            -D sonar.projectVersion=${BRANCH_NAME}-${BUILD_NUMBER} \
                            -D sonar.sources=./src
                            '''
                        } 

                        // Run Quality Gate
                        timeout(time: 1, unit: 'MINUTES') { // Just in case something goes wrong,
                            def qg = waitForQualityGate() // Reuse taskId previously collected by withSonarQube
                            if (qg.status != 'OK') {
                                error "Pipeline aborted due to quality gate failure: ${qg.status}"
                            }
                        } // End timeout
                    } // End script
                } // End container
            } // End steps
        } // End stage

        // ***** Stage OWASP *****
        stage('OWASP Dependency Check') {
            steps {
                container('java-node') {
                    script {
                        // Install application dependency
                        //sh '''cd src/ && npm install --package-lock && cd ../'''

                        // Start OWASP Dependency Check
                        dependencyCheck(
                            additionalArguments: "--data /home/jenkins/dependency-check-data --out dependency-check-report.xml",
                            odcInstallation: "dependency-check"
                        )

                        // Publish report to Jenkins
                        dependencyCheckPublisher(
                            pattern: 'dependency-check-report.xml'
                        )

                        // Remove application dependency
                        //sh'''rm -rf src/node_modules src/package-lock.json'''
                    } // End script
                } // End container
            } // End steps
        } // End stage
      
        // ***** Stage Build *****
        stage('Build ratings Docker Image and push') {
            steps {
                container('docker') {
                    script {
                        
                        //sh "docker login -u phurits -p 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 https://ghcr.io"
                    // Do docker login authentication
                    docker.withRegistry('https://ghcr.io','registry-bookinfo') {
                        // Do docker build and docker push
                        docker.build("ghcr.io/phurits/opsta-bootcamp-bookinfo-ratings:${ENV_NAME}").push()
                    }// End docker
                    }//End script
                }//End container
            }//End steps
        }//End stage

        // // ***** Stage Anchore *****
        // stage('Anchore Engine') {
        //     steps {
        //         container('jnlp') {
        //             script {
        //                 // dend Docker Image to Anchore Analyzer
        //                 writeFile file: 'anchore_images' , text: "ghcr.io/phurits/opsta-bootcamp-bookinfo-ratings:${ENV_NAME}"
        //                 anchore name: 'anchore_images' , bailOnFail: false
        //             } // End script
        //         } // End container
        //     } // End steps
        // } // End stage

        // ***** Stage scan container image *****
        stage('Scan image with trivy') {
            steps {
                container('trivy') {
                    script {
                        withCredentials([usernamePassword(credentialsId: 'registry-bookinfo', passwordVariable: 'TRIVY_PASSWORD', usernameVariable: 'TRIVY_USERNAME')]) {
                            // Download template 
                            sh 'wget https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/html.tpl'

                            // Scan Image
                            sh "trivy image --format template --template '@./html.tpl' -o trivy-results.html ghcr.io/phurits/opsta-bootcamp-bookinfo-ratings:${ENV_NAME}"
                            
                            // recordIssues tools: [trivy(pattern: 'trivy-results.html')]
                            // archiveArtifacts artifacts: 'trivy-results.html'

                            publishHTML([
                                allowMissing: false,
                                alwaysLinkToLastBuild: false,
                                keepAll: true,
                                reportDir: '.',
                                reportFiles: 'trivy-results.html',
                                reportName: 'Trivy Scan Report',
                                reportTitles: ''
                            ])
                        } // End withCredentials
                    } // End script
                } // End container
            } // End steps
        } // End stage

        stage('Deploy ratings with Helm Chart') {
            steps {
                // Run on Helm container
                container('helm') {
                    script {
                        // Use kubeconfig from Jenkins Credential
                        withKubeConfig([credentialsId: 'gke-kubeconfig']) {
                            // Use Google Service Account IAM for Kubernetes Authentication
                            //withCredentials([file(credentialsId: 'gke-sa-key-json', variable: 'GOOGLE_APPLICATION_CREDENTIALS')]) {
                                
                                // Run the helm command with the service account key JSON file
                                sh "helm upgrade bookinfo-${ENV_NAME}-ratings k8s/helm -f k8s/helm-values/values-bookinfo-${ENV_NAME}-ratings.yaml \
                                    --wait --namespace ais-bookinfo-${ENV_NAME} --set extraEnv.COMMIT_ID=${scmVars.GIT_COMMIT}"

                            //} // End withCredentials
                        } // End withKubeConfig
                    } // End script
                } // End container
            } // End steps
        } // End stage

  }// End stages
}// End pipeline