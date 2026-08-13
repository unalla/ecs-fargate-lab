# Provenance Lab — rebuild, don't patch

A working end-to-end demonstration of the container patching model: a small
Flask app on ECS Fargate behind an ALB, rebuilt and redeployed by GitHub
Actions, with the base image pinned by digest and every image signed before it
is allowed to run.

The app's only job is to tell you which image is serving you, so rolling
deploys and rollbacks are things you can watch rather than things you assert.

---

## What's here

```
app/            Flask app — /, /healthz, /version, /simulate-failure
tests/          unit suite (the gate) + post-deploy smoke test
Dockerfile      multi-stage, non-root, base pinned via build arg
base-image.lock the pinned base digest — the one line CVE refreshes change
infra/          Terraform: VPC, ALB, ECR, ECS, GitHub OIDC role
.github/        deploy pipeline + weekly base-image refresh
```

---

## Setup

### 1. Push to GitHub

```bash
gh repo create ecs-fargate-lab --private --source=. --push
```

### 2. Stand up the infrastructure

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # set github_repo, optionally allowed_cidr
terraform init
terraform apply
```

Takes about four minutes, mostly the load balancer.

### 3. Wire GitHub to AWS

```bash
terraform output github_variables
```

Add each as a repository **variable** (not a secret — none of these are
sensitive) under Settings → Secrets and variables → Actions → Variables:

`AWS_REGION`, `AWS_ROLE_ARN`, `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_SERVICE`,
`ECS_TASK_FAMILY`, `APP_URL`

Note there is no AWS access key anywhere. The pipeline authenticates by
exchanging a short-lived GitHub OIDC token for temporary credentials, scoped
by IAM condition to this repository alone.

### 4. Seed the base image pin

```bash
DIGEST=$(docker buildx imagetools inspect python:3.12-slim --format '{{.Manifest.Digest}}')
sed -i '' "s|^BASE_IMAGE_DIGEST=.*|BASE_IMAGE_DIGEST=${DIGEST}|" base-image.lock  # drop the '' on Linux
git commit -am "chore: seed base image digest" && git push
```

That push triggers the first real deployment. Open `APP_URL` when it goes
green.

---

## The four things worth actually running

### 1. A code change

Edit the headline in `app/templates/index.html`, push to main. Watch the
pipeline: tests → build → scan → sign → verify → rolling deploy → smoke test.
Refresh the page during the deploy and you'll see the digest and task hostname
change as the ALB shifts traffic. Nothing was ever down.

### 2. A base image refresh — the patching story

```bash
gh workflow run "base image refresh"
```

If upstream has published a newer base, you get a pull request that changes
one line. The PR runs the same test suite a feature change runs. Merge it and
the patch ships; leave it red and production keeps running the old image,
untouched.

To force the demo, hand-edit `base-image.lock` to an older digest and let the
workflow discover the drift.

Look at the build log for the rebuild: the dependency and application layers
are cache hits. You are not reinstalling the app — you are swapping an 80 MB
OS layer underneath it.

### 3. A failed deployment rolling itself back

Break the health check on purpose:

```python
# app/app.py — inside healthz()
return jsonify({"status": "broken"}), 500
```

Push it. The new tasks start, fail the target-group health check twice, the
ECS circuit breaker abandons the deployment and restores the previous task
definition. The workflow goes red. **The site never stopped serving the old
image.** This is the single most persuasive thing to show an app team that is
afraid of patching.

### 4. The signature gate

```bash
# Push an unsigned image straight to ECR, bypassing the pipeline
docker build -t $ECR_REPO:rogue . && docker push $ECR_REPO:rogue
cosign verify --certificate-identity-regexp ".*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  $ECR_REPO:rogue
```

Verification fails, so the deploy job would refuse it. An engineer cannot ship
an image built on their laptop.

---

## Cost

Roughly **$27/month** if you leave everything running, and the ALB is most of
it. Park the compute when you're not using it:

```bash
make stop    # desired-count 0 — Fargate bills per second
make start
make destroy # when you're done
```

Two deliberate choices keep this cheap: no NAT Gateway (tasks run in public
subnets, protected by security groups — see the note in `infra/network.tf`
about why production would use VPC endpoints instead), and Container Insights
off.

---

## What this doesn't cover

Worth knowing before you present it:

- **No admission controller.** ECS has no equivalent, so signature enforcement
  lives in the pipeline. On EKS this becomes a Kyverno or OPA policy enforced
  cluster-side, which is strictly stronger — the pipeline can be bypassed, an
  admission webhook can't.
- **No HTTPS.** Add an ACM certificate and a 443 listener; it's about ten
  lines. Skipped here because it needs a domain.
- **Layer 1 only.** This handles OS CVEs. Vulnerabilities in your own
  dependencies live in layer 3 and need SCA scanning and a dependency bot —
  a separate workstream.
- **Stateless.** Anything holding sessions or local state needs real work
  before rolling replacement is safe.

---

## Porting this to EKS

The Dockerfile, tests, scanning, and signing steps are unchanged. What changes:

| ECS | EKS |
|---|---|
| task definition | Deployment manifest |
| `ecs update-service` | `kubectl set image` or Argo CD sync |
| deployment circuit breaker | `maxUnavailable` + readiness probes, or Argo Rollouts |
| pipeline-side `cosign verify` | Kyverno / OPA Gatekeeper admission policy |
| target group health check | readiness and liveness probes |

The pattern is identical. Only the deploy verb differs — which is a useful
thing to be able to say out loud.
