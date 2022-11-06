pipeline {
    agent any
    stages {
        stage('Init'){
            steps {
                sh '''#!/bin/bash
                       git init
                       git remote add origin ssh://LeafOS-Jenkins@review.leafos.org:29418/LeafOS-Project/leaf_www
                '''
            }
        }
        stage('Pick commit'){
            steps {
                sh '''#!/bin/bash
                        git fetch origin refs/changes/${GERRIT_CHANGE_NUMBER: -2}/${GERRIT_CHANGE_NUMBER}/${GERRIT_PATCHSET_NUMBER}
                        git checkout FETCH_HEAD
                '''
            }
        }
        stage('Go'){
            steps {
                sh '''#!/bin/bash
                        set -e
                        sed -i s@^baseurl:\\ \\"@baseurl:\\ \\"/${GERRIT_CHANGE_NUMBER}@g _config.yml
                        sed -i s@^url:\\ \\"@url:\\ \\"https://www-preview.leafos.org@g _config.yml
                        jekyll build
                        if [ $? == 0 ]; then
                                ssh -p 29418 LeafOS-Jenkins@review.leafos.org gerrit review -n OWNER --tag Jenkins --label Verified=+1 -m \\'"PASS: Jenkins : ${BUILD_URL}console\nBuild successful for change $GERRIT_CHANGE_NUMBER, patchset $GERRIT_PATCHSET_NUMBER.\nPreview available at https://www-preview.leafos.org/${GERRIT_CHANGE_NUMBER}"\\' $GERRIT_CHANGE_NUMBER,$GERRIT_PATCHSET_NUMBER
                        else
                                ssh -p 29418 LeafOS-Jenkins@review.leafos.org gerrit review -n OWNER --tag Jenkins --label Verified=-1 -m \\'"FAIL: Jenkins : ${BUILD_URL}console\nBuild failed for change $GERRIT_CHANGE_NUMBER, patchset $GERRIT_PATCHSET_NUMBER"\\' $GERRIT_CHANGE_NUMBER,$GERRIT_PATCHSET_NUMBER
                        fi
                        mkdir -p /var/www/www-preview.leafos.org/${GERRIT_CHANGE_NUMBER}
                        rsync -rh _site/ jenkins@10.2.0.1:/var/www/www-preview.leafos.org/${GERRIT_CHANGE_NUMBER} --delete
                '''
            }
        }
    }
    post {
        always {
            deleteDir()
        }
    }
}
