# How this repository is driven

This file is for coding agents working in this checkout. `CONTRIBUTING.md` is the source of truth for
conventions; this file records the one rule that is not obvious from it, because an agent with push access
could quietly route around the review gate.

## The agent opens the pull request. The owner merges it.

An agent working here may branch, commit, push and open a pull request. It must then **stop**.

- **Do** run `make test` before opening the PR, and put what you tested in the body.
- **Do** follow the title, body and branch conventions in `CONTRIBUTING.md`.
- **Do** open a fresh branch per concern, and delete nothing else.
- **Do not** run `gh pr merge`, in any mode.
- **Do not** run `gh pr merge --auto`, and do not add a workflow that merges on checks passing.
- **Do not** push to `main`, force-push, or bypass the `main-protection` ruleset.
- **Do not** merge an older open PR to make room for newer work.

The only exception is an explicit instruction to merge one named pull request — "merge #7", not "land the
fix". Absent that, an open PR is the finished state of the work.

### Why this is a rule and not a preference

The repository owner is a bypass actor on the `main-protection` ruleset, so a merge from the owner's own
credentials skips the required review, the last-push approval and the status checks. The ruleset cannot
tell "the owner approved this" from "an agent used the owner's `gh` token", so the gate has to be held by
discipline rather than by GitHub. PRs opened and merged by the same actor within minutes leave a history
that looks reviewed and was not — see PRs #1 and #2, merged with zero reviews.

An agent that opens the PR and stops keeps the human approval real: the owner reads the diff, and because
they are not the pusher, the "require last push approval" rule means a follow-up commit from the agent
needs their re-approval rather than silently riding along.

## Branches

Leave merged branches alone unless asked: local and `origin/` branches for a merged PR are kept on purpose
so the work can still be inspected, even though `CONTRIBUTING.md` describes them as deleted on merge.
