#!/usr/bin/env groovy

pipeline {
    agent any
    parameters {
        string(name: 'JENKINS_BUILD_JOB', defaultValue: 'leaf_release', description: '')
        string(name: 'JENKINS_LEAF_VERSION', defaultValue: '2.0', description: '')
        string(name: 'JENKINS_REPOPICK', defaultValue: '', description: '')
        choice(name: 'JENKINS_BUILDTYPE', choices: ['user', 'userdebug', 'eng'], description: '')
        choice(name: 'JENKINS_RELEASETYPE', choices: ['alpha', 'beta', 'stable'], description: '')
        booleanParam(name: 'JENKINS_TELEGRAM', defaultValue: true, description: '')
    }
    options {
        disableConcurrentBuilds()
    }
    stages {
        stage('Clone leaf_devices') {
            steps {
                sh '''#!/bin/bash
                       rm -rf leaf_devices
                       git clone https://git.leafos.org/LeafOS-Project/leaf_devices -b leaf-$JENKINS_LEAF_VERSION
                '''
            }
        }
        stage('Trigger builds') {
            steps {
                script {
                    devices = readYaml(file: 'leaf_devices/devices.yaml')
                    for (family in devices) {
                        i = 0
                        shouldSync = true
                        for (device in family.device) {
                            shouldClean = i >= (family.device.size() - 1)
                            build job:"${JENKINS_BUILD_JOB}", parameters:[
                                string(name: 'JENKINS_LEAF_VERSION', value: "${JENKINS_LEAF_VERSION}"),
                                string(name: 'JENKINS_DEVICE', value: "${device}"),
                                string(name: 'JENKINS_LUNCH', value: ''),
                                string(name: 'JENKINS_REPOPICK', value: "${JENKINS_REPOPICK}"),
                                string(name: 'JENKINS_BUILDTYPE', value: "${JENKINS_BUILDTYPE}"),
                                string(name: 'JENKINS_RELEASETYPE', value: "${JENKINS_RELEASETYPE}"),
                                booleanParam(name: 'JENKINS_CLEAN', value: "${shouldClean}"),
                                booleanParam(name: 'JENKINS_REPOSYNC', value: "${shouldSync}"),
                                booleanParam(name: 'JENKINS_TELEGRAM', value: "${JENKINS_TELEGRAM}")
                            ]
                            i++
                            shouldSync = false
                        }
                    }
                }
            }
        }
    }
}
