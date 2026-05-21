from kfp import dsl
from kfp.dsl import Input, Output, Dataset, Model, Metrics


@dsl.component(base_image="k3d-registry.localhost:5000/fraud-component:v1")
def train(
    train_data: Input[Dataset],
    model_out: Output[Model],
    mlflow_tracking_uri: str,
    experiment_name: str,
):
    import os
    import pandas as pd
    import lightgbm as lgb
    import mlflow
    import mlflow.lightgbm
    from sklearn.metrics import roc_auc_score

    os.environ["MLFLOW_S3_ENDPOINT_URL"] = "http://minio.platform.svc.cluster.local:9000"
    os.environ["AWS_ACCESS_KEY_ID"] = "minio"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "minio123"

    mlflow.set_tracking_uri(mlflow_tracking_uri)
    mlflow.set_experiment(experiment_name)

    df = pd.read_parquet(train_data.path)
    X_train = df.drop(columns=["Class"])
    y_train = df["Class"]

    fraud_rate = y_train.mean()
    scale_pos_weight = (1 - fraud_rate) / fraud_rate

    params = {
        "objective": "binary",
        "metric": "auc",
        "n_estimators": 300,
        "learning_rate": 0.05,
        "num_leaves": 63,
        "scale_pos_weight": scale_pos_weight,
        "random_state": 42,
        "n_jobs": 2,
        "verbose": -1,
    }

    with mlflow.start_run() as run:
        mlflow.log_params(params)

        model = lgb.LGBMClassifier(**params)
        model.fit(X_train, y_train)

        train_auc = roc_auc_score(y_train, model.predict_proba(X_train)[:, 1])
        mlflow.log_metric("train_auc", train_auc)

        mlflow.lightgbm.log_model(model, "model")

        print(f"MLflow run_id={run.info.run_id}, train_auc={train_auc:.4f}")

    model.booster_.save_model(model_out.path)
    print(f"Model saved to {model_out.path}")
