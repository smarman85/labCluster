# Better Approval Workflows (No Cluster Access Required)

## Problem
The default Flagger loadtester requires `kubectl exec` access to approve deployments. This is problematic because:
- ❌ Requires cluster admin access
- ❌ Not audit-friendly  
- ❌ Doesn't integrate with existing approval workflows
- ❌ Hard to automate or delegate

## Solution 1: GitOps Approval ⭐ Recommended

**How it works:**
1. Deploy new version
2. Flagger starts canary analysis
3. To approve: Create PR setting `skipAnalysis: true`
4. Merge PR → Flux applies change → Flagger promotes
5. Optional: Auto-revert `skipAnalysis: false` after promotion

**Pros:**
- ✅ No cluster access needed
- ✅ Full Git audit trail
- ✅ Works with existing PR approval workflows
- ✅ Can require multiple approvers via GitHub/GitLab
- ✅ Integrates with CI/CD

**Workflow:**
```bash
# 1. Canary is waiting for approval
kubectl get canary podinfo
# STATUS: Progressing

# 2. Create approval commit
git checkout -b approve-podinfo-v1.2.3
# Edit: skipAnalysis: false → true
git commit -m "Approve podinfo v1.2.3 promotion"
git push

# 3. Create PR, get approvals, merge

# 4. Flux applies, Flagger promotes immediately

# 5. Auto-revert skipAnalysis back to false
git checkout -b reset-skip-analysis  
# Edit: skipAnalysis: true → false
git commit -m "Reset skipAnalysis for next deployment"
```

**⚠️ IMPORTANT: Auto-reset required!**

Without auto-reset, `skipAnalysis: true` persists and ALL future deployments skip analysis.

**Automation Option A: GitHub Actions** (Recommended for GitOps)
```bash
# Already set up at .github/workflows/reset-skip-analysis.yaml
# Automatically reverts skipAnalysis: true → false after merge to main
```

**Automation Option B: Kubernetes CronJob**
```bash
# Deploy the reset controller
kubectl apply -f experiments/flagger/flagger-reset-controller.yaml

# Checks every 5 minutes for Canaries with:
# - skipAnalysis: true
# - status: Succeeded
# Then patches them back to skipAnalysis: false
```

**Manual reset** (if automation fails):
```bash
kubectl patch canary podinfo -n test \
  --type=merge \
  -p '{"spec":{"skipAnalysis":false}}'
```

## Solution 2: External Webhook Service

**How it works:**
1. Point `confirm-promotion` webhook to external service
2. Service polls GitHub PR, Slack, Jira, etc. for approval
3. Returns 200 when approved, 403 to reject

**Example services you could build:**

### GitHub PR Approval Bot
```python
# Simple Flask endpoint
@app.route('/api/flagger/approve', methods=['POST'])
def approve_deployment():
    canary = request.json
    repo = "your-org/your-repo"
    
    # Check if PR with label "deploy-approved" exists
    pr = github.get_pr_with_label(repo, "deploy-approved")
    
    if pr and pr.state == "open" and pr.approved:
        return jsonify({"approved": True}), 200
    else:
        return jsonify({"approved": False}), 403
```

### Slack Approval Bot
```python
@app.route('/slack/approve', methods=['POST'])
def slack_approve():
    canary = request.json
    
    # Post message to Slack with approve/reject buttons
    slack.post_message(
        channel="#deployments",
        text=f"Approve {canary['name']} deployment?",
        buttons=["Approve", "Reject"]
    )
    
    # Check if approved (cached from button click handler)
    if slack.is_approved(canary['name']):
        return jsonify({"approved": True}), 200
    else:
        return jsonify({"waiting": True}), 500  # Retry
```

**Pros:**
- ✅ No cluster access needed
- ✅ Integrate with existing tools (Slack, PagerDuty, Jira)
- ✅ Can notify on-call engineers
- ✅ Audit trail in external system

**Cons:**
- ❌ Requires running external service
- ❌ More complex setup

## Solution 3: Suspend + Manual Patch

**How it works:**
1. Set `suspend: true` in Canary spec
2. Flagger pauses all analysis
3. Manually test canary
4. Use `kubectl patch` to set `suspend: false` and `skipAnalysis: true`

```bash
# Pause canary
kubectl patch canary podinfo -n test -p '{"spec":{"suspend":true}}'

# Test canary...

# Resume and promote
kubectl patch canary podinfo -n test -p '{"spec":{"suspend":false,"skipAnalysis":true}}'

# Reset for next deployment
kubectl patch canary podinfo -n test -p '{"spec":{"skipAnalysis":false}}'
```

**Pros:**
- ✅ Simple
- ✅ No external dependencies

**Cons:**
- ❌ Still requires cluster access
- ❌ Less audit trail than GitOps

## Solution 4: Zero Analysis (Always Promote)

**When appropriate:**
- You have extensive pre-merge testing
- Rollback is fast and automated
- Risk tolerance is higher

```yaml
spec:
  skipAnalysis: true  # Always skip, always promote
```

Or remove `analysis` entirely and use just:
```yaml
spec:
  analysis:
    interval: 30s
    iterations: 1    # Minimal wait
    threshold: 0     # Never rollback
    # No metrics, no webhooks
```

## Recommendation

**For production:** Use **GitOps Approval** (Solution 1)
- Leverages existing Git workflow
- No new infrastructure
- Best audit trail
- No cluster access needed

**For staging:** Use **Zero Analysis** (Solution 4)  
- Fast feedback
- Build confidence in prod approval process

**For complex orgs:** Use **External Webhook** (Solution 2)
- Integrate with PagerDuty, ServiceNow, etc.
- Multi-stage approvals
- Rich notifications
