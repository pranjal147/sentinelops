from kfp import dsl
from kfp.dsl import Input, Output, Dataset


@dsl.component(base_image="k3d-registry.localhost:5000/fraud-component:v1")
def preprocess(
    data: Input[Dataset],
    train_out: Output[Dataset],
    test_out: Output[Dataset],
    test_size: float = 0.2,
    random_state: int = 42,
):
    import pandas as pd
    from sklearn.model_selection import train_test_split

    df = pd.read_csv(data.path)

    # Drop the time column — not predictive across days
    df = df.drop(columns=["Time"])

    X = df.drop(columns=["Class"])
    y = df["Class"]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=test_size, random_state=random_state, stratify=y
    )

    train_df = X_train.copy()
    train_df["Class"] = y_train.values
    test_df = X_test.copy()
    test_df["Class"] = y_test.values

    train_df.to_parquet(train_out.path, index=False)
    test_df.to_parquet(test_out.path, index=False)

    fraud_rate = y_train.mean()
    scale_pos_weight = (1 - fraud_rate) / fraud_rate
    print(
        f"Train: {len(train_df)} rows, fraud_rate={fraud_rate:.4f}, "
        f"scale_pos_weight={scale_pos_weight:.1f}"
    )
    print(f"Test:  {len(test_df)} rows")
