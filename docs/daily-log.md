# SentinelOps Daily Log

This file tracks daily progress, blockers, and time spent across the 20-day build.

---

## Day 0 — Environment Bootstrap (2026-05-16)

**Goal:** All tools installed, accounts ready, repo bootstrapped.

### Completed
- [ ] WSL2 + Docker Desktop verified
- [ ] All CLI tools installed (see scripts/verify-environment.sh output)
- [ ] AWS account created, MFA enabled, IAM user `sentinelops-dev` configured
- [ ] AWS budget alerts set at $25/$50/$75/$90
- [ ] `aws sts get-caller-identity` returns expected account
- [ ] Anthropic API key in ~/.bashrc, test curl returns response
- [ ] GitHub CLI authenticated, repo pushed
- [ ] Smoke test: k3d cluster create → nginx pod → delete cluster works
- [ ] Kaggle API token saved to ~/.kaggle/kaggle.json

### Time spent
X hours

### Blockers
None / [list]
