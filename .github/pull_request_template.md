<!--
PR title: <type>(<scope>): <imperative subject>   e.g. feat(provider): add Zalo QR sign-in
The title becomes the squash commit on main and is checked by the Conventions workflow.
Types: feat fix perf refactor test docs build ci chore revert — see CONTRIBUTING.md.
-->

## What does this change?

<!-- One or two sentences. Link the issue if there is one: "Closes #12". -->

## How did you verify it?

<!--
- `make test` / `make test-live` result
- What you clicked, dragged or signed in to
- For UI work: attach before/after screenshots (make render writes PNGs)
-->

## Checklist

- [ ] PR title follows `type(scope): subject` — it becomes the squash commit on `main`
- [ ] `make test` is green
- [ ] `make test-live` is green if this touches provider detection, `WebSession`, or `ProviderCatalog`
- [ ] No credentials, cookies or provider responses are stored, logged or proxied
- [ ] UI changes include a screenshot
- [ ] Provider page changes are reflected in `ProviderSpec` selectors in the same PR
- [ ] `CHANGELOG.md` updated under *Unreleased* for user-visible changes
