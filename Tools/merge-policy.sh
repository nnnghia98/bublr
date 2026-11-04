#!/usr/bin/env bash
# Re-apply the repository ruleset that decides who is allowed to merge into the default branch.
#
# Policy: pull requests into main can be merged by contributors and admins only.
#   - Repository admins (the owner) bypass every rule, so they can merge without a second reviewer.
#   - The write role is the bypass for the rest: a contributor you invited as a collaborator can
#     merge their PR once reviews and checks pass.
#   - Everyone else - fork authors, readers, triage - can open a PR but can never merge it,
#     because the "update" rule stops them from pushing to the branch at all.
#
# Run this after renaming the default branch, transferring the repository, or editing the rules by
# hand:
#   Tools/merge-policy.sh                # target the repo of the current directory
#   Tools/merge-policy.sh owner/repo     # target an explicit repo
#
# Requires: gh, authenticated with admin access to the repository.
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
NAME="main-protection"

payload="$(mktemp -t bublr-merge-policy)"
trap 'rm -f "$payload"' EXIT

cat >"$payload" <<'JSON'
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" },
    { "actor_id": 2, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" }
  ],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "update" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": true,
        "required_review_thread_resolution": true,
        "allowed_merge_methods": ["squash", "merge"]
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [
          { "context": "Build & self-test" }
        ]
      }
    }
  ]
}
JSON

ruleset_id="$(gh api --paginate "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$NAME\") | .id" | head -n 1)"

if [ -n "$ruleset_id" ]; then
  gh api -X PUT "repos/$REPO/rulesets/$ruleset_id" --input "$payload" >/dev/null
  echo "Updated ruleset '$NAME' on $REPO"
else
  ruleset_id="$(gh api -X POST "repos/$REPO/rulesets" --input "$payload" --jq .id)"
  echo "Created ruleset '$NAME' on $REPO"
fi

gh api "repos/$REPO/rulesets/$ruleset_id" --jq '
  "rules:  \(.rules | map(.type) | join(", ")),
   bypass: \(.bypass_actors | map("\(.actor_type)#\(.actor_id) \(.bypass_mode)") | join(", "))"'
