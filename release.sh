#!/usr/bin/env bash
set -e

# avoid the release loop by checking if the latest commit is a release commit
readonly local last_release_commit_hash=$(git log --author="$GIT_RELEASE_BOT_NAME" --pretty=format:"%H" -1)
echo "Last $GIT_RELEASE_BOT_NAME commit: ${last_release_commit_hash}"
echo "Current commit: ${GITHUB_SHA}"
if [[ "${last_release_commit_hash}" = "${GITHUB_SHA}" ]]; then
     echo "Skipping for $GIT_RELEASE_BOT_NAME commit"
     exit 0
fi

# Filter the branch to execute the release on
readonly local branch=${GITHUB_REF##*/}
echo "Current branch: ${branch}"
if [[ -n "$RELEASE_BRANCH_NAME" && ! "${branch}" = "$RELEASE_BRANCH_NAME" ]]; then
     echo "Skipping for ${branch} branch"
     exit 0
fi

# Making sure we are on top of the branch
echo "Git checkout branch ${GITHUB_REF##*/}"
git checkout ${GITHUB_REF##*/}
echo "Git reset hard to ${GITHUB_SHA}"
git reset --hard ${GITHUB_SHA}

# This script will do a release of the artifact according to http://maven.apache.org/maven-release/maven-release-plugin/
echo "Setup git user name to '$GIT_RELEASE_BOT_NAME'"
git config --global user.name "$GIT_RELEASE_BOT_NAME";
echo "Setup git user email to '$GIT_RELEASE_BOT_EMAIL'"
git config --global user.email "$GIT_RELEASE_BOT_EMAIL";

# Setup GPG
echo "GPG_ENABLED '$GPG_ENABLED'"
if [[ $GPG_ENABLED == "true" ]]; then
     echo "Enable GPG signing in git config"
     git config --global commit.gpgsign true
     echo "Using the GPG key ID $GPG_KEY_ID"
     git config --global user.signingkey $GPG_KEY_ID
     echo "GPG_KEY_ID = $GPG_KEY_ID"
     echo "Import the GPG key"
     echo  "$GPG_KEY" | base64 -d > private.key
     gpg --import ./private.key
     rm ./private.key
else
  echo "GPG signing is not enabled"
fi
echo "Override the java home as gitactions is seting up the JAVA_HOME env variable"
JAVA_HOME="/usr/local/openjdk-11/"
# Setup maven local repo
if [[ -n "$MAVEN_LOCAL_REPO_PATH" ]]; then
     MAVEN_REPO_LOCAL="-Dmaven.repo.local=$MAVEN_LOCAL_REPO_PATH"
fi

# ===============MAVEN RELEASE====================================================
echo "-------> Do mvn $MAVEN_REPO_LOCAL release:prepare with arguments $MAVEN_RELEASE_ARGS"
mvn $MAVEN_REPO_LOCAL release:prepare -Dusername=$GITHUB_ACCESS_TOKEN $MAVEN_RELEASE_ARGS

echo "-------> Do mvn $MAVEN_REPO_LOCAL release:perform with arguments $MAVEN_RELEASE_ARGS"
mvn $MAVEN_REPO_LOCAL release:perform -Dusername=$GITHUB_ACCESS_TOKEN $MAVEN_RELEASE_ARGS

# ===============MAVEN DEPLY & UPLOAD ARTIFACTS TO GITHUB PAKCAGES=================
#echo "-------> MAVEN_RELEASE_PUBLISH $MAVEN_RELEASE_PUBLISH"
#if [[ $MAVEN_RELEASE_PUBLISH == "true" ]]; then
#     echo "-------> Do mvn deploy with arguments $MAVEN_PUBLISH_ARGS"
#     mvn -f target/checkout/pom.xml deploy -Dusername=$GITHUB_ACCESS_TOKEN $MAVEN_PUBLISH_ARGS
#else
#  echo "Release deploy skipped."
#fi

echo "-------> MAVEN_SNAPSHOT_PUBLISH $MAVEN_SNAPSHOT_PUBLISH"
if [[ $MAVEN_SNAPSHOT_PUBLISH == "true" ]]; then
     echo "-------> Do mvn deploy with arguments $MAVEN_PUBLISH_ARGS"
     mvn deploy -Dusername=$GITHUB_ACCESS_TOKEN $MAVEN_PUBLISH_ARGS
else
  echo "Snapshot deploy skipped."
fi

# ===============Maven BUILD & PUSH DOCKER IAMGE======================================

echo "MAVEN_RELEASE_PUSH_DOCKER $MAVEN_RELEASE_PUSH_DOCKER"
if [[ $MAVEN_RELEASE_PUSH_DOCKER == "true" ]]; then
     echo "Run mvn dockerfile:build dockerfile:push -Ddockerfile.skip=false -Ddockerfile.repository=$MAVEN_DOCKER_FILE_REPOSITORY -Ddockerfile.username=$MAVEN_DOCKER_USER -Ddockerfile.password=$MAVEN_DOCKER_PASSWORD $MAVEN_DOCKER_ARGS"
     mvn -f target/checkout/pom.xml dockerfile:build dockerfile:push -Ddockerfile.skip=false -Ddockerfile.repository=$MAVEN_DOCKER_FILE_REPOSITORY -Ddockerfile.username=$MAVEN_DOCKER_USER -Ddockerfile.password=$MAVEN_DOCKER_PASSWORD $MAVEN_DOCKER_ARGS
else
  echo "Push release docker image skipped."
fi

echo "MAVEN_SNAPSHOT_PUSH_DOCKER $MAVEN_SNAPSHOT_PUSH_DOCKER"
if [[ $MAVEN_SNAPSHOT_PUSH_DOCKER == "true" ]]; then
     echo "Do mvn dockerfile:build dockerfile:push -Ddockerfile.skip=false -Ddockerfile.repository=$MAVEN_DOCKER_FILE_REPOSITORY -Ddockerfile.username=$MAVEN_DOCKER_USER -Ddockerfile.password=$MAVEN_DOCKER_PASSWORD $MAVEN_DOCKER_ARGS"
     mvn deploy dockerfile:build dockerfile:push -Ddockerfile.skip=false -Ddockerfile.repository=$MAVEN_DOCKER_FILE_REPOSITORY -Ddockerfile.username=$MAVEN_DOCKER_USER -Ddockerfile.password=$MAVEN_DOCKER_PASSWORD $MAVEN_DOCKER_ARGS
else
  echo "Push shapshot docker image skipped."
fi