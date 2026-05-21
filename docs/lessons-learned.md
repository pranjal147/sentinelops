# SentinelOps — Lessons Learned

Hard-won fixes and patterns. Read this before starting each day.

---

## Environment: WSL2 + Docker Desktop + k3d

### L01 — Docker credential helper breaks after restart
**Symptom:** `docker push` fails with `exec: "docker-credential-desktop.exe": executable file not found`
**Fix:** Run once after every restart:
```bash
python3 -c "
import json, os
cfg = os.path.expanduser('~/.docker/config.json')
with open(cfg) as f: d = json.load(f)
d.pop('credsStore', None); d.pop('credHelpers', None)
with open(cfg, 'w') as f: json.dump(d, f, indent=2)
"
```

### L02 — Docker Desktop hangs on large image operations
**Symptom:** `k3d image import`, `ctr images import`, or `docker save` of images >500MB hang indefinitely and lock the entire WSL2/Docker Desktop session.
**Fix:** Never preload images >200MB via `ctr import`. Let k3d registry pull happen naturally — it works for images up to ~900MB. If hung: Task Manager → kill Docker Backend → `wsl --shutdown` → restart Docker Desktop.
**Prevention:** Do not run `docker save` / `ctr images import` for large images. Use the registry pull path.

### L03 — Docker build cache corruption after crashes
**Symptom:** Build "succeeds" but image has corrupted `.so` files (`invalid ELF header`).
**Fix:** Always use `docker build --no-cache` after any Docker Desktop crash or restart.
**Prevention:** After any unexpected restart, assume build cache is dirty.

### L04 — k3d registry hostname mismatch
**Symptom:** Pods get `ErrImagePull` even though image was pushed to `localhost:5000`.
**Root cause:** k3d nodes only mirror `k3d-registry.localhost:5000`, not `localhost:5000`. From Docker host, push to `localhost:5000`. In component `base_image`, use `k3d-registry.localhost:5000`.
**Rule:** Push = `localhost:5000/image:tag`. Reference in code = `k3d-registry.localhost:5000/image:tag`.

### L05 — Always verify image tag in pipeline.yaml before submitting
**Symptom:** Pipeline fails with wrong image version despite running `sed` to update.
**Fix:** Always run this before submitting:
```bash
grep "base_image\|image:" pipeline.yaml | head -5
```
**Prevention:** After every `sed` update, grep the compiled yaml to confirm.

### L06 — `python:3.11-slim` missing `libgomp.so.1` (LightGBM dependency)
**Symptom:** `OSError: libgomp.so.1: cannot open shared object file`
**Fix:** Multi-stage Dockerfile — copy libgomp from full image, no apt-get needed:
```dockerfile
FROM python:3.11 AS base
FROM python:3.11-slim
COPY --from=base /usr/lib/x86_64-linux-gnu/libgomp.so.1 /usr/lib/x86_64-linux-gnu/libgomp.so.1
COPY --from=base /usr/lib/x86_64-linux-gnu/libgomp.so.1.0.0 /usr/lib/x86_64-linux-gnu/libgomp.so.1.0.0
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
```
**Why not apt-get:** `deb.debian.org` is unreachable from Docker Desktop WSL2 builds.

### L07 — WSL2 file sync: Cursor edits Windows path, kubectl runs in WSL2
**Symptom:** Changes made in Cursor on Windows don't appear in WSL2 `~/sentinelops`.
**Fix:** After editing in Cursor, sync with:
```bash
rsync -av --include="*/" --include="*.py" --include="*.yaml" --include="*.yml" \
  --include="*.tf" --include="*.sh" --include="Dockerfile" \
  --include="*.txt" --include="*.md" --include="Makefile" --exclude="*" \
  "/mnt/c/Users/E1970/OneDrive - Uncia Technologies Private Limited/SentinelOps/" \
  ~/sentinelops/
```
**Or:** git commit from Windows-mounted path then `git pull` in WSL2.

### L08 — Port-forwards die silently, restart them after every WSL session
```bash
export KUBECONFIG=~/.kube/sentinelops-local.yaml
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8888:80 &
kubectl port-forward -n mlops svc/mlflow 5000:5000 &
kubectl port-forward -n platform svc/minio 9000:9000 &
```

### L09 — `ctr images rm` to clean corrupted images before registry pull
**Symptom:** Pod gets `invalid ELF header` despite image being in registry.
**Root cause:** A previous failed/hung `ctr import` left a corrupted image tag on the node. Registry pull is skipped because the tag already exists locally.
**Fix:**
```bash
for node in k3d-sentinelops-local-server-0 k3d-sentinelops-local-agent-0 k3d-sentinelops-local-agent-1; do
  docker exec $node ctr images rm <image>:<tag> 2>/dev/null || true
done
```

### L10 — KFP pipeline `auc_threshold` must be realistic for Day 4
**Note:** LightGBM on credit card fraud dataset without extensive tuning achieves AUC ~0.90. Set `auc_threshold=0.88` as the quality gate for Day 4. Improve in Day 5+.

---

## Start-of-Day Checklist (run every session)

```bash
# 1. Fix docker credentials
python3 -c "import json,os; cfg=os.path.expanduser('~/.docker/config.json'); d=json.load(open(cfg)); d.pop('credsStore',None); d.pop('credHelpers',None); json.dump(d,open(cfg,'w'),indent=2)"

# 2. Set kubeconfig
export KUBECONFIG=~/.kube/sentinelops-local.yaml

# 3. Verify cluster
kubectl get nodes

# 4. Check pod health
kubectl get pods -n platform | grep -v Running
kubectl get pods -n mlops | grep -v Running
kubectl get pods -n kubeflow | grep -v "Running\|Completed"

# 5. Start port-forwards
kubectl port-forward -n kubeflow svc/ml-pipeline-ui 8888:80 &
kubectl port-forward -n mlops svc/mlflow 5000:5000 &
```
