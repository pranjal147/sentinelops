"""
Fraud detection pipeline — LightGBM binary classifier on IEEE-CIS dataset.
Compiles to pipeline.yaml; submit via KFP UI or kfp.Client.
"""
import kfp
from kfp import dsl
from kfp import compiler

from components.load_data import load_data
from components.validate_data import validate_data
from components.preprocess import preprocess
from components.train import train
from components.evaluate import evaluate


@dsl.pipeline(name="fraud-lgbm-pipeline", description="LightGBM fraud detection")
def fraud_pipeline(
    s3_endpoint: str = "http://minio.platform.svc.cluster.local:9000",
    s3_bucket: str = "datasets",
    s3_key: str = "fraud/creditcard.csv",
    mlflow_tracking_uri: str = "http://mlflow.mlops.svc.cluster.local:5000",
    experiment_name: str = "fraud-lgbm",
    auc_threshold: float = 0.88,
):
    load_task = load_data(
        s3_endpoint=s3_endpoint,
        s3_bucket=s3_bucket,
        s3_key=s3_key,
    )

    validate_task = validate_data(data=load_task.outputs["data_out"])
    validate_task.after(load_task)

    preprocess_task = preprocess(data=load_task.outputs["data_out"])
    preprocess_task.after(validate_task)

    train_task = train(
        train_data=preprocess_task.outputs["train_out"],
        mlflow_tracking_uri=mlflow_tracking_uri,
        experiment_name=experiment_name,
    )

    evaluate_task = evaluate(
        test_data=preprocess_task.outputs["test_out"],
        model=train_task.outputs["model_out"],
        auc_threshold=auc_threshold,
    )


if __name__ == "__main__":
    compiler.Compiler().compile(fraud_pipeline, "pipeline.yaml")
    print("Compiled → pipeline.yaml")
