#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

failures=0
local_path_pattern='(/Users/[^/]+/(Desktop|Documents|Downloads|Workspaces)/|/Volumes/[^/]+/|\.ssh/)'
secret_pattern='(BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|sk_live_[A-Za-z0-9]{16,}|xox[baprs]-[A-Za-z0-9-]{16,})'
sensitive_file_pattern='(^|/)(\.env($|\.)|[^/]+\.(key|pem|p12|pfx|mobileprovision|provisionprofile)|secrets?($|/))'
consumer_email_pattern='[A-Za-z0-9._%+-]+@(gmail|icloud|me|outlook|hotmail|yahoo)\.[A-Za-z]{2,}'

function report_failure() {
    local heading="$1"
    local details="$2"
    print "FAIL: $heading" >&2
    print "$details" >&2
    failures=$((failures + 1))
}

tracked_paths="$(git grep -I -n -E "$local_path_pattern" -- \
    ':!scripts/security-audit.sh' ':!docs/plans/**' || true)"
[[ -z "$tracked_paths" ]] || report_failure "tracked personal/local paths" "$tracked_paths"

tracked_secrets="$(git grep -I -n -E "$secret_pattern" -- \
    ':!scripts/security-audit.sh' ':!docs/plans/**' || true)"
[[ -z "$tracked_secrets" ]] || report_failure "tracked secret-shaped values" "$tracked_secrets"

tracked_consumer_emails="$(git grep -I -n -E "$consumer_email_pattern" -- \
    ':!scripts/security-audit.sh' ':!docs/plans/**' || true)"
[[ -z "$tracked_consumer_emails" ]] || report_failure "tracked consumer email addresses" "$tracked_consumer_emails"

sensitive_files="$(git ls-files | /usr/bin/grep -E "$sensitive_file_pattern" || true)"
[[ -z "$sensitive_files" ]] || report_failure "tracked sensitive filenames" "$sensitive_files"

history_paths="$(git --no-pager log --all -G "$local_path_pattern" \
    --format='%H %s' --name-only || true)"
[[ -z "$history_paths" ]] || report_failure "local paths in Git history" "$history_paths"

history_secrets="$(git --no-pager log --all -G "$secret_pattern" \
    --format='%H %s' --name-only || true)"
[[ -z "$history_secrets" ]] || report_failure "secret-shaped values in Git history" "$history_secrets"

app_binary="dist/Exnano Fabric.app/Contents/MacOS/Fabric"
if [[ -x "$app_binary" ]]; then
    binary_leaks="$(/usr/bin/strings "$app_binary" | \
        /usr/bin/grep -E "$local_path_pattern|$secret_pattern|$consumer_email_pattern" || true)"
    [[ -z "$binary_leaks" ]] || report_failure "sensitive values in release binary" "$binary_leaks"

    unsafe_rpaths="$(/usr/bin/otool -l "$app_binary" | /usr/bin/awk \
        '/cmd LC_RPATH/ { getline; getline; print $2 }' | \
        /usr/bin/grep -E '^(/Users/|/Volumes/|/Applications/Xcode\.app/|/Library/Developer/)' || true)"
    [[ -z "$unsafe_rpaths" ]] || report_failure "development-machine rpaths in release binary" "$unsafe_rpaths"
fi

print "Public Git author identities (review intentionally; not treated as secrets):"
git --no-pager log --all --format='%an <%ae>' | /usr/bin/sort -u

if (( failures > 0 )); then
    print "Security audit failed with $failures finding group(s)." >&2
    exit 1
fi

print "Security audit passed."
