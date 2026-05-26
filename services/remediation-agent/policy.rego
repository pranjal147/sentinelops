package remediation

import future.keywords.if
import future.keywords.in

# Namespaces where restarts are allowed
allowed_namespaces := {"serving", "platform", "mlops", "kubeflow"}

# Deployments that can be scaled down (never scale to 0 unintentionally)
scalable_deployments := {
    "serving/fraud-lgbm-predictor",
    "serving/prediction-logger",
    "platform/anomaly-detector",
}

# Maximum restarts allowed per deployment in a rolling window (enforced externally)
max_restarts := 3

default allow := false
default deny_reason := "unknown policy violation"

# Allow restart_pod for known namespaces with warning/critical severity
allow if {
    input.action == "restart_pod"
    input.namespace in allowed_namespaces
    input.severity in {"warning", "critical"}
}

# Allow scale_deployment only for known scalable deployments
allow if {
    input.action == "scale_deployment"
    key := concat("/", [input.namespace, input.deployment])
    key in scalable_deployments
    input.replicas >= 1
    input.replicas <= 5
}

# Allow get_pod_status always (read-only)
allow if {
    input.action == "get_pod_status"
}

# Deny anything touching kube-system regardless of other rules
deny_reason := "kube-system namespace is protected" if {
    input.namespace == "kube-system"
}

deny_reason := "scaling to 0 replicas is not allowed" if {
    input.action == "scale_deployment"
    input.replicas == 0
}

deny_reason := "deployment not in scalable list" if {
    input.action == "scale_deployment"
    key := concat("/", [input.namespace, input.deployment])
    not key in scalable_deployments
}
