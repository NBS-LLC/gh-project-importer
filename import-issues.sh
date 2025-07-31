#!/bin/bash

# A script to read a JSON file and create GitHub issues and labels.

usage() {
    cat <<'EOF'
Usage: $0 -f <path> [options]

Imports issues and labels from a JSON file into a GitHub repository.

This script requires the GH_PROJECT_IMPORTER_TOKEN environment variable to be set
with a GitHub Personal Access Token (PAT) with 'repo' scope.

Dependencies:
- gh (the GitHub CLI): https://cli.github.com/
- jq (a command-line JSON processor): https://stedolan.github.io/jq/

Required:
  -f, --file <path>      Path to the input JSON file.

Options:
  -r, --repo <owner/repo> Target GitHub repository.
                         (Default: the repo for the current directory)
  --execute              Actually create labels and issues. Defaults to dry-run.
  -h, --help             Display this help message.
EOF
}

set -euo pipefail

# --- Global Variables ---
JSON_FILE=""
REPO=""
DRY_RUN=true
DEFAULT_LABEL_COLOR="ededed" # A neutral grey
gh_args=()

# --- Function Definitions ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -f | --file)
            JSON_FILE="$2"
            shift 2
            ;;
        -r | --repo)
            REPO="$2"
            shift 2
            ;;
        --execute)
            DRY_RUN=false
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        esac
    done
}

validate_input() {
    if [ -z "$JSON_FILE" ]; then
        echo "Error: Input JSON file must be specified with -f or --file." >&2
        echo
        usage
        exit 1
    fi

    if [ ! -f "$JSON_FILE" ]; then
        echo "Error: File not found at '$JSON_FILE'" >&2
        exit 1
    fi
}

check_dependencies() {
    if ! command -v jq &>/dev/null; then
        echo "Error: 'jq' is not installed. Please install it to continue." >&2
        exit 1
    fi

    if ! command -v gh &>/dev/null; then
        echo "Error: GitHub CLI 'gh' is not installed. Please install it to continue." >&2
        exit 1
    fi

    if [ -z "${GH_PROJECT_IMPORTER_TOKEN:-}" ]; then
        echo "Error: The GH_PROJECT_IMPORTER_TOKEN environment variable is not set." >&2
        echo "Please set it to a GitHub Personal Access Token with 'repo' scope." >&2
        exit 1
    fi

    export GH_TOKEN="$GH_PROJECT_IMPORTER_TOKEN"
    echo "Verifying token..."
    if ! gh api user &>/dev/null; then
        echo "Error: The provided GH_PROJECT_IMPORTER_TOKEN is invalid or has insufficient permissions." >&2
        echo "Please ensure it is a valid Personal Access Token with 'repo' scope." >&2
        exit 1
    fi
    echo "Token is valid."
}

confirm_execution_mode() {
    if [ "$DRY_RUN" = false ]; then
        echo "--- EXECUTE MODE ---"
        echo "This script WILL create labels and issues on GitHub."
        echo "You have 5 seconds to cancel (Ctrl+C)..."
        sleep 5
    else
        echo "--- DRY RUN MODE ---"
        echo "No changes will be made. To execute for real, run with the --execute flag."
        echo
    fi
}

prepare_gh_command() {
    if [ -n "$REPO" ]; then
        gh_args+=(--repo "$REPO")
    fi
}

create_labels() {
    echo "STEP 1: Processing labels from $JSON_FILE..."
    UNIQUE_LABELS=$(jq -r '.[].labels[]' "$JSON_FILE" | sort -u)

    for label in $UNIQUE_LABELS; do
        if gh "${gh_args[@]:+${gh_args[@]}}" label list --json name | jq --arg name "$label" -e 'any(.[] | .name == $name)' &>/dev/null; then
            echo "Label '$label' already exists. Skipping."
        else
            if [ "$DRY_RUN" = true ]; then
                echo "[DRY RUN] Would create label: '$label'"
            else
                echo "Creating label: '$label'..."
                gh "${gh_args[@]:+${gh_args[@]}}" label create "$label" --color "$DEFAULT_LABEL_COLOR" --description "Auto-created by project importer"
            fi
        fi
    done
    echo
}

create_issues() {
    echo "STEP 2: Processing issues from $JSON_FILE..."
    while IFS= read -r issue_json; do
        title=$(echo "$issue_json" | jq -r '.title')
        body=$(echo "$issue_json" | jq -r '.description')
        labels=$(echo "$issue_json" | jq -r '.labels | join(",")')

        if [ "$DRY_RUN" = true ]; then
            truncated_body="$body"
            if [ ${#body} -gt 80 ]; then
                truncated_body="${body:0:77}..."
            fi
            printf "[DRY RUN] Would create issue:\n"
            printf "  Title:  %s\n" "$title"
            printf "  Labels: %s\n" "$labels"
            printf "  Body:   %s\n\n" "$truncated_body"
        else
            echo "Creating issue: '$title'..."
            gh "${gh_args[@]:+${gh_args[@]}}" issue create --title "$title" --body "$body" --label "$labels"
        fi
    done < <(jq -c '.[]' "$JSON_FILE")
}

main() {
    parse_args "$@"
    validate_input
    check_dependencies
    confirm_execution_mode
    prepare_gh_command
    create_labels
    create_issues
    echo -e "\nScript finished."
}

# --- Script Execution ---
main "$@"
