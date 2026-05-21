from kfp import dsl
from kfp.dsl import Input, Output, Dataset, Model, Metrics


@dsl.component(base_image="k3d-registry.localhost:5000/fraud-component:v1")
def evaluate(
    test_data: Input[Dataset],
    model: Input[Model],
    metrics_out: Output[Metrics],
    auc_threshold: float = 0.95,
):
    import pandas as pd
    import lightgbm as lgb
    from sklearn.metrics import roc_auc_score, average_precision_score

    df = pd.read_parquet(test_data.path)
    X_test = df.drop(columns=["Class"])
    y_test = df["Class"]

    booster = lgb.Booster(model_file=model.path)
    y_prob = booster.predict(X_test)

    auc = roc_auc_score(y_test, y_prob)
    avg_precision = average_precision_score(y_test, y_prob)

    metrics_out.log_metric("test_auc", auc)
    metrics_out.log_metric("avg_precision", avg_precision)

    print(f"test_auc={auc:.4f}, avg_precision={avg_precision:.4f}")

    if auc < auc_threshold:
        raise ValueError(
            f"AUC {auc:.4f} below threshold {auc_threshold}. Aborting."
        )

    print(f"Model passed quality gate (AUC {auc:.4f} >= {auc_threshold})")
