#!/bin/bash

# Path to local DVWA repository mirror
LOCAL_REPO="/home/jenkins/Desktop/code/DVWA"

# Remote repository URL (read-only)
REMOTE_REPO="https://github.com/raghavanrrs/DVWA.git"

# Branches to track
BRANCHES=("master" "dev" "prod")

# Clone if not exists
if [ ! -d "$LOCAL_REPO/.git" ]; then
  echo "Cloning DVWA repo for first time..."
  git clone --mirror "$REMOTE_REPO" "$LOCAL_REPO"
  if [ $? -ne 0 ]; then
    echo "Initial clone failed"
    exit 1
  fi
fi

cd "$LOCAL_REPO" || { echo "Cannot access repo directory"; exit 1; }

# Fetch all updates and tags
git fetch --all --tags

# Update all branches locally from remote, force reset
for branch in "${BRANCHES[@]}"; do
  # Check if branch exists locally, create if missing
  if ! git show-ref --verify --quiet "refs/heads/$branch"; then
    git branch "$branch" "origin/$branch"
  fi
  git checkout "$branch"
  git reset --hard "origin/$branch"
done

# Clean untracked files and directories
git clean -fd

# Verify composer.lock presence
if [ -f composer.lock ]; then
  echo "composer.lock exists in the codebase."
else
  echo "WARNING: composer.lock file is missing."
fi

echo "DVWA local mirror update completed successfully."
