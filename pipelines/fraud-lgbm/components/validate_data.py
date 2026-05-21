from kfp import dsl
from kfp.dsl import Input, Dataset


@dsl.component(base_image="k3d-registry.localhost:5000/fraud-component:v1")
def validate_data(data: Input[Dataset]) -> str:
    import pandas as pd

    df = pd.read_csv(data.path)

    checks = {
        "row_count": len(df) >= 200_000,
        "has_class_column": "Class" in df.columns,
        "no_missing_values": df.isnull().sum().sum() == 0,
        "fraud_rate_plausible": 0.001 <= df["Class"].mean() <= 0.01,
        "feature_count": len(df.columns) == 31,
    }

    failures = [name for name, passed in checks.items() if not passed]
    if failures:
        raise ValueError(f"Validation failed: {failures}")

    summary = (
        f"rows={len(df)}, fraud_rate={df['Class'].mean():.4f}, "
        f"cols={len(df.columns)}"
    )
    print(f"Validation passed: {summary}")
    return summary
