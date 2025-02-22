#!/usr/bin/env bash
set -eu

mkdir -p /github/workflow
cp /action/problem-matcher.json /github/workflow/problem-matcher.json

git clone --depth 1 -b 3.1.0 https://github.com/WordPress/WordPress-Coding-Standards.git ~/wpcs
git config --global --add safe.directory "$(pwd)"

diff_lines() {
  path=""
  line=""
  while IFS= read -r REPLY; do
     esc=$(printf '\033')
     if echo "$REPLY" | grep -qE '\-\-\- (a/)?.*'; then
         continue
     elif echo "$REPLY" | grep -qE '\+\+\+ (b/)?([^[:blank:]'"$esc"']+).*'; then
         path=$(echo "$REPLY" | sed -E 's/\+\+\+ (b\/)?([^[:blank:]'"$esc"']+).*/\2/')
     elif echo "$REPLY" | grep -qE '@@ -[0-9]+(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@.*'; then
         line=$(echo "$REPLY" | sed -E 's/@@ -[0-9]+(,[0-9]+)? \+([0-9]+)(,[0-9]+)? @@.*/\2/')
     elif echo "$REPLY" | grep -qE '^('"$esc"'\[[0-9;]*m)*([\\ +-])'; then
         echo "$path:$line:$REPLY"
         if echo "${REPLY}" | grep -qE '^('"$esc"'\[[0-9;]*m)*([\ +-])'; then
             line=$((line+1))
         fi
     fi
  done
}

filter_by_changed_lines() {
    changedLines="$1"
    fileName=
    fileLine=
    exitCode=0

    while IFS= read -r line; do
        if echo "$line" | grep -q -E '<file name="(\/github\/workspace\/)?([^"]+)'; then
            fileName=$(echo "$line" | sed -E 's/.*<file name="(\/github\/workspace\/)?([^"]+).*/\2/')
            echo "$line"
        elif echo "$line" | grep -q -E '<error line="([^"]+)'; then
            fileLine=$(echo "$line" | sed -E 's/.*<error line="([^"]+).*/\1/')
            if echo "$changedLines" | grep -qx "$fileName:$fileLine"; then
                exitCode=1
                echo "$line"
            fi
        else
            echo "$line"
        fi
    done
    exit "$exitCode"
}

clean_diff_output() {
  step1=$(git diff -U0 --diff-filter=d "${COMPARE_FROM_REF}" "${COMPARE_TO_REF}")
  step2=$(echo "${step1}" | diff_lines)
  step3=$(echo "${step2}" | grep -ve ':-')
  step4=$(echo "${step3}" | sed 's/:+.*//')
  step5=$(echo "${step4}" | sed 's/:\\.*//')

  echo "${step5}"
}

# Sets installed_paths WITHOUT passing changed files to PHPCS.
decide_installed_paths() {
  standards="$1"
  # Just set installed_paths once, no appended files
  ${INPUT_PHPCS_BIN_PATH} --config-set installed_paths "${standards}"
}

INPUT_ONLY_CHANGED_FILES=${INPUT_ONLY_CHANGED_FILES:-${INPUT_ONLY_CHANGED_LINES:-"false"}}

# Identify changed refs
if [ "${INPUT_ONLY_CHANGED_FILES}" = "true" ]; then
    if [ "${GITHUB_EVENT_NAME}" = "pull_request" ]; then
        COMPARE_FROM="origin/${GITHUB_BASE_REF}"
        COMPARE_TO="origin/${GITHUB_HEAD_REF}"
        COMPARE_FROM_REF=$(git merge-base "${COMPARE_FROM}" "${COMPARE_TO}")
        COMPARE_TO_REF=${COMPARE_TO}
    else
        COMPARE_FROM="HEAD^"
        COMPARE_TO="HEAD"
        COMPARE_FROM_REF="HEAD^"
        COMPARE_TO_REF="HEAD"
    fi
    echo "Will only check changed files (${COMPARE_FROM_REF} -> ${COMPARE_TO_REF})"

    # SAFELY gather changed .php files with null-termination
    set +e
    CHANGED_FILES=$(
      git diff --name-only -z --diff-filter=d "${COMPARE_FROM_REF}" "${COMPARE_TO_REF}" \
      | xargs -0 -I{} sh -c '
          case "$1" in
            *.php) echo "$1";;
          esac
        ' _ {}
    )
    set -e

    echo "Changed .php files (raw multiline variable):"
    echo "${CHANGED_FILES}"

    # echo "=== DEBUG: CHANGED_FILES in hex ==="
    # # Show hex dump to spot any \r or weird chars
    # echo "${CHANGED_FILES}" | od -An -tx1
    # echo "=== END DEBUG ==="

else
    echo "Will check all files"
    CHANGED_FILES=""
fi

# Clone or set up standards
if [ "${INPUT_STANDARD}" = "WordPress-VIP-Go" ] || [ "${INPUT_STANDARD}" = "WordPressVIPMinimum" ]; then
    echo "Setting up VIPCS"
    git clone --depth 1 -b 3.0.1 https://github.com/Automattic/VIP-Coding-Standards.git ${HOME}/vipcs
    git clone https://github.com/sirbrillig/phpcs-variable-analysis ${HOME}/variable-analysis
    decide_installed_paths "${HOME}/wpcs,${HOME}/vipcs,${HOME}/variable-analysis"

elif [ "${INPUT_STANDARD}" = "10up-Default" ]; then
    echo "Setting up 10up-Default"
    git clone https://github.com/10up/phpcs-composer ${HOME}/10up
    git clone https://github.com/PHPCompatibility/PHPCompatibilityWP ${HOME}/phpcompatwp
    git clone https://github.com/PHPCompatibility/PHPCompatibility ${HOME}/phpcompat
    git clone https://github.com/PHPCompatibility/PHPCompatibilityParagonie ${HOME}/phpcompat-paragonie
    git clone --depth 1 --branch 1.0.12 https://github.com/PHPCSStandards/PHPCSUtils ${HOME}/phpcsutils
    git clone --depth 1 --branch develop https://github.com/PHPCSStandards/PHPCSExtra ${HOME}/phpcs-extra
    git clone https://github.com/Automattic/VIP-Coding-Standards ${HOME}/vipcs
    git clone https://github.com/sirbrillig/phpcs-variable-analysis ${HOME}/variable-analysis

    decide_installed_paths "${HOME}/wpcs,${HOME}/10up/10up-Default,${HOME}/phpcompatwp/PHPCompatibilityWP,${HOME}/phpcompat/PHPCompatibility,${HOME}/phpcompat-paragonie/PHPCompatibilityParagonieSodiumCompat,${HOME}/phpcompat-paragonie/PHPCompatibilityParagonieRandomCompat,${HOME}/phpcsutils/PHPCSUtils,${HOME}/vipcs,${HOME}/variable-analysis,${HOME}/phpcs-extra"

elif [ -z "${INPUT_STANDARD_REPO}" ] || [ "${INPUT_STANDARD_REPO}" = "false" ]; then
    decide_installed_paths "${HOME}/wpcs"
else
    echo "Standard repository: ${INPUT_STANDARD_REPO}"
    git clone -b "${INPUT_REPO_BRANCH}" "${INPUT_STANDARD_REPO}" ${HOME}/cs
    decide_installed_paths "${HOME}/wpcs,${HOME}/cs"
fi

if [ -z "${INPUT_EXCLUDES}" ]; then
    EXCLUDES="node_modules,vendor"
else
    EXCLUDES="node_modules,vendor,${INPUT_EXCLUDES}"
    echo "Excluding: ${EXCLUDES}"
fi

phpcs -i

echo "::add-matcher::${RUNNER_TEMP}/_github_workflow/problem-matcher.json"

# Decide warnings
if [ -z "${INPUT_ENABLE_WARNINGS}" ] || [ "${INPUT_ENABLE_WARNINGS}" = "false" ]; then
    WARNING_FLAG="-n"
    echo "Check for warnings disabled"
else
    WARNING_FLAG=""
    echo "Check for warnings enabled"
fi

# Detect local config
if [ -f ".phpcs.xml" ] || [ -f "phpcs.xml" ] || [ -f ".phpcs.xml.dist" ] || [ -f "phpcs.xml.dist" ]; then
    HAS_CONFIG=true
else
    HAS_CONFIG=false
fi

# Prepare final arguments in an array
REPORT_FLAG="--report=checkstyle"
if [ -n "${INPUT_EXTRA_ARGS}" ]; then
    EXTRA_ARGS_ARRAY=( ${INPUT_EXTRA_ARGS} )
else
    EXTRA_ARGS_ARRAY=()
fi

# Put changed files into an array line-by-line (if any)
mapfile -t CHANGED_ARRAY <<EOF
${CHANGED_FILES}
EOF

echo "Final changed file count: ${#CHANGED_ARRAY[@]}"
for f in "${CHANGED_ARRAY[@]}"; do
  echo "  -> $f"
done

# Final scanning
if [ "${HAS_CONFIG}" = true ] && [ "${INPUT_USE_LOCAL_CONFIG}" = "true" ]; then
    # We rely on local phpcs.xml / phpcs.xml.dist
    echo "Using local config"

    if [ "${INPUT_ONLY_CHANGED_FILES}" = "true" ]; then
        if [ "${INPUT_ONLY_CHANGED_LINES}" = "true" ]; then
            echo "Linting only-changed-lines using summary, then filtering..."
            echo "PHPCS command: phpcs ${WARNING_FLAG} --report=summary [CHANGED_ARRAY] + filter_by_changed_lines"
            set +e
            printf '%s\n' "${CHANGED_ARRAY[@]}" | xargs -r ${INPUT_PHPCS_BIN_PATH} -v -p ${WARNING_FLAG} --report=summary "${EXTRA_ARGS_ARRAY[@]}" \
            | filter_by_changed_lines "$(clean_diff_output)"
            status=$?
            set -e
        else
            echo "Linting only the changed files with local config..."
            echo "PHPCS command: phpcs ${WARNING_FLAG} ${REPORT_FLAG} [CHANGED_ARRAY]"
            printf '%s\n' "${CHANGED_ARRAY[@]}" | xargs -r ${INPUT_PHPCS_BIN_PATH} ${WARNING_FLAG} ${REPORT_FLAG} "${EXTRA_ARGS_ARRAY[@]}"
            status=$?
        fi
    else
        # Scan entire codebase with local config
        echo "Scanning entire codebase with local config"
        echo "PHPCS command: phpcs ${WARNING_FLAG} ${REPORT_FLAG} [EXTRA_ARGS_ARRAY]"
        ${INPUT_PHPCS_BIN_PATH} ${WARNING_FLAG} ${REPORT_FLAG} "${EXTRA_ARGS_ARRAY[@]}"
        status=$?
    fi
else
    # No local config => explicitly pass --standard
    echo "No local config or not using it => using --standard=${INPUT_STANDARD}"

    if [ "${INPUT_ONLY_CHANGED_FILES}" = "true" ]; then
        if [ "${INPUT_ONLY_CHANGED_LINES}" = "true" ]; then
            echo "Linting only-changed-lines with explicit standard..."
            set +e
            printf '%s\n' "${CHANGED_ARRAY[@]}" | xargs -r ${INPUT_PHPCS_BIN_PATH} ${WARNING_FLAG} ${REPORT_FLAG} --standard=${INPUT_STANDARD} --extensions=php "${EXTRA_ARGS_ARRAY[@]}" \
            | filter_by_changed_lines "$(clean_diff_output)"
            status=$?
            set -e
        else
            echo "Linting only the changed files with standard=${INPUT_STANDARD}"
            printf '%s\n' "${CHANGED_ARRAY[@]}" | xargs -r ${INPUT_PHPCS_BIN_PATH} ${WARNING_FLAG} ${REPORT_FLAG} --standard=${INPUT_STANDARD} --extensions=php "${EXTRA_ARGS_ARRAY[@]}"
            status=$?
        fi
    else
        # Scan entire repo using standard
        echo "Scanning entire repo with standard=${INPUT_STANDARD}"
        ${INPUT_PHPCS_BIN_PATH} \
          ${WARNING_FLAG} \
          ${REPORT_FLAG} \
          --standard="${INPUT_STANDARD}" \
          --ignore="${EXCLUDES}" \
          --extensions=php \
          "${INPUT_PATHS}" \
          "${EXTRA_ARGS_ARRAY[@]}"
        status=$?
    fi
fi

echo "::remove-matcher owner=phpcs::"

exit $status
