# Flagger Manual Approval Setup

## Quick Start

### Option 1: GitOps Approval (Recommended)

1. **Deploy the canary config:**
   ```bash
   kubectl apply -f podinfo-canary-gitops-approval.yaml
   ```

2. **Set up auto-reset (REQUIRED):**
   
   **If using GitHub Actions:**
   ```bash
   # GitHub Actions workflow is at .github/workflows/reset-skip-analysis.yaml
   # It auto-reverts skipAnalysis after merge
   # Make sure GitHub Actions has write permissions
   ```
   
   **OR using Kubernetes CronJob:**
   ```bash
   kubectl apply -f flagger-reset-controller.yaml
   # Checks every 5 min and resets skipAnalysis after promotion
   ```

3. **Approve a deployment:**
   ```bash
   # When canary is waiting, create PR:
   git checkout -b approve-deployment
   # Change: skipAnalysis: false → skipAnalysis: true
   git add experiments/flagger/podinfo-canary-gitops-approval.yaml
   git commit -m "Approve podinfo deployment"
   git push
   # Create PR, get reviews, merge
   ```

4. **Auto-reset happens automatically** via GitHub Actions or CronJob

### Option 2: External Webhook

See `podinfo-canary-external-webhook.yaml` for examples of integrating with:
- GitHub PR approvals
- Slack bots
- Custom approval services

## Files

- `podinfo-canary-gitops-approval.yaml` - Main config with skipAnalysis toggle
- `flagger-reset-controller.yaml` - K8s CronJob to auto-reset skipAnalysis
- `APPROVAL_WORKFLOWS.md` - Complete guide with all options
- `podinfo-canary-external-webhook.yaml` - External webhook examples

## Why Auto-Reset is Critical

Without auto-reset:
1. You set `skipAnalysis: true` to approve deployment
2. Deployment promotes successfully
3. **Next deployment ALSO has skipAnalysis: true**
4. All future deployments skip analysis automatically ❌

With auto-reset:
1. You set `skipAnalysis: true` to approve
2. Deployment promotes
3. Auto-reset changes it back to `false`
4. Next deployment requires manual approval again ✅

## Monitoring

```bash
# Watch canary status
kubectl get canary podinfo -n test -w

# Check if skipAnalysis needs reset
kubectl get canary podinfo -n test -o jsonpath='{.spec.skipAnalysis}'

# Manually reset if needed
kubectl patch canary podinfo -n test --type=merge -p '{"spec":{"skipAnalysis":false}}'
```
