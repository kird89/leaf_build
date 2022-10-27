#!/usr/bin/env groovy

pipeline {
    agent any
    parameters {
        string(name: 'JENKINS_LEAF_VERSION', defaultValue: '2.0', description: '')
        string(name: 'JENKINS_DEVICE', defaultValue: 'beyond1lte', description: '')
        string(name: 'JENKINS_LUNCH', defaultValue: '', description: '')
        string(name: 'JENKINS_REPOPICK', defaultValue: '', description: '')
        choice(name: 'JENKINS_BUILDTYPE', choices: ['user', 'userdebug', 'eng'], description: '')
        choice(name: 'JENKINS_RELEASETYPE', choices: ['alpha', 'beta', 'stable'], description: '')
        booleanParam(name: 'JENKINS_CLEAN', defaultValue: true, description: '')
        booleanParam(name: 'JENKINS_TELEGRAM', defaultValue: true, description: '')
    }
    environment {
        def BUILDDATE = sh(script: "date -u +%Y%m%d_%H%M", returnStdout: true)
    }
    options {
       checkoutToSubdirectory('jenkins/build')
       disableConcurrentBuilds()
    }
    stages {
        stage('Sync') {
            steps {
                script {
                    currentBuild.displayName = "${currentBuild.displayName} (${params.JENKINS_DEVICE})"
                    env.STAGE = "sync"
                }
                leaf_build("sync")
            }
        }
        stage('Build target-files-package') {
            steps {
                script {
                    env.STAGE = "target-files"
                }
                leaf_build("target-files")
            }
        }
        stage('Sign') {
            steps {
                script {
                    env.STAGE = "sign"
                }
                leaf_build("sign")
            }
        }
        stage('Build ota-package') {
            steps {
                script {
                    env.STAGE = "ota-package"
                }
                leaf_build("ota-package")
            }
        }
        stage('Upload build') {
            steps {
                script {
                    env.STAGE = "upload"
                }
                leaf_build("upload")
            }
        }
    }
    post {
        always {
            script {
                env.BUILD_STATUS = "${currentBuild.currentResult}"
            }
            leaf_build("cleanup")
        }
    }
}

def leaf_build(String stage) {
    sh '''#!/bin/bash
    source "$WORKSPACE/jenkins/build/jenkins/leaf-build.sh"
    '''+stage+'''
    '''
}
