#!/bin/sh

# Copyright 2025 Dave Kessler <activethrasher00@gmail.com>
#
# Pre-push git hook script: this automates some of the self-review process 
# and checks your branch for PR readiness to reduce spurious build attempts 
# in CI/CD pipelines.
#
# To override githooks add the --no-verify argument to your build command.
#
# Steps:
# 1) require a successful build
# 2) require detekt pass
# 3) check for untracked files
# 4) check for untracked changes
# 5) check if up-to-date with origin. 
# 6) check if current branch exists on the remote and local is up-to-date
#TODO: require passing the Android lint rules, or a set of custom lint rules
#TODO: ensure there are no blocked files/credentials/keystores committed in the source
#TODO: branch naming conventions are observed? define this check with a commented example
#TODO: require incremental version or release tag bump

hooks_dir=$(dirname "$0")
ERROR='\033[0;31m'

# Navigate to project root
cd "$hooks_dir/../.."

echo "Building project..."

# 1) Clean and build
./gradlew clean build 

# 2) Verify the build result
if [ $? -ne 0 ]; then
    echo -e "\n${ERROR}Build failed. Aborting push.$(tput sgr0)"
    exit 1
fi

# 3) Run detekt if it's configured
TASK="detekt"
if ./gradlew tasks --all | grep -qw "^$TASK"
    then
		./gradlew detekt --continue
		# Check detekt result
		if [ $? -ne 0 ]; then
			echo -e "\n${ERROR}Detekt failed. Aborting push."
			exit 1
		fi
	else
		echo -e "\nWarning: detekt not configured for this project."
fi

# TODO: Run lint rules.  Create custom lint rules

# 4) Check for untracked files
if [[ $(git ls-files --others --exclude-standard) ]]; then
    echo -e "\n${ERROR}Check failed: Untracked files found.$(tput sgr0)"
    exit 1
fi

# 5) Check for uncommitted changes
if [[ -n "$(git status --porcelain)" ]]; then
    echo -e "\n${ERROR}Check failed. Uncommitted changes found.$(tput sgr0)"
    exit 1
fi

# 6) Update remote tracking information
git fetch

# 7) Check if the local branch is behind the remote
DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | cut -d: -f2 | sed -e 's/^[[:space:]]*//')
BEHIND_COUNT=$(git rev-list --count HEAD..origin/$DEFAULT_BRANCH)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if git rev-parse --verify --quiet remotes/origin/my-branch; then
    echo "Local branch already exists on the remote 'origin'."
else
    echo "Local branch does not exist on the remote (or is not tracked)."
fi

# 8) Check if the local is behind the origin HEAD state
if [ "$BEHIND_COUNT" -gt 0 ]; then
    echo -e "\n${ERROR}Check failed: $CURRENT_BRANCH is behind origin/main by $BEHIND_COUNT commits.$(tput sgr0)"
    exit 1
else
    echo -e "\nPass: $CURRENT_BRANCH is up-to-date with origin/$DEFAULT_BRANCH."
fi

# 9) Check if the local status is up-to-date with the remote
LOCAL_GIT_STATUS=$(git status -uno)

# 10) Check the output for specific keywords and indicate potential conflicts
if [[ "$LOCAL_GIT_STATUS" == *"up to date"* ]]; then
    echo "Branch is up to date with the remote."
elif [[ "$LOCAL_GIT_STATUS" == *"behind"* ]]; then
    echo "${ERROR}Branch is behind the remote (needs pull).$(tput sgr0)"
    exit 1
elif [[ "$LOCAL_GIT_STATUS" == *"ahead"* ]]; then
    echo "${ERROR}Branch is ahead of the remote (needs push).$(tput sgr0)"
    exit 1
elif [[ "$LOCAL_GIT_STATUS" == *"diverged"* ]]; then
    echo "${ERROR}Branch has diverged (needs merge/rebase).$(tput sgr0)"
    exit 1
elif [[ "$LOCAL_GIT_STATUS" == *"Changes not staged for commit"* ]]; then
	# we should have already failed here in a previous step
    :
else
	echo -e "\n${ERROR}Branch has an unhandled case $LOCAL_GIT_STATUS."
fi

echo -e "Pre-checks succeeded. Proceeding with push.\n"

# All pre-push checks passed
exit 0
