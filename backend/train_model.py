import pandas as pd
import joblib

from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report


# --------------------------------------------------
# 1. LOAD DATASET
# --------------------------------------------------
df = pd.read_csv("triage_dataset.csv")
# Clean column names
df.columns = (
    df.columns
    .str.replace(r"\\t", "", regex=True)
    .str.replace("\t", "", regex=False)
    .str.strip()
)

print("Dataset loaded successfully.")
print("Number of rows:", len(df))
print("Columns:", list(df.columns))


# --------------------------------------------------
# 2. CHECK REQUIRED COLUMNS
# --------------------------------------------------

required_columns = ["symptoms", "category"]

for column in required_columns:
    if column not in df.columns:
        raise ValueError(
            f"Required column '{column}' was not found in the CSV."
        )


# --------------------------------------------------
# 3. CLEAN DATA
# --------------------------------------------------

df = df[["symptoms", "category"]].copy()

df["symptoms"] = df["symptoms"].fillna("").astype(str)
df["category"] = df["category"].fillna("").astype(str).str.strip().str.upper()

# Remove rows where symptoms or category is empty
df = df[
    (df["symptoms"].str.strip() != "") &
    (df["category"].str.strip() != "")
]

print("\nCategories found:")
print(df["category"].value_counts())


# --------------------------------------------------
# 4. INPUT AND OUTPUT
# --------------------------------------------------

X = df["symptoms"]
y = df["category"]


# --------------------------------------------------
# 5. SPLIT DATA
# --------------------------------------------------

X_train, X_test, y_train, y_test = train_test_split(
    X,
    y,
    test_size=0.20,
    random_state=42,
    stratify=y
)


# --------------------------------------------------
# 6. CREATE MACHINE LEARNING PIPELINE
# --------------------------------------------------

model = Pipeline([
    (
        "tfidf",
        TfidfVectorizer(
            lowercase=True,
            ngram_range=(1, 2)
        )
    ),
    (
        "classifier",
        LogisticRegression(
            max_iter=1000
        )
    )
])


# --------------------------------------------------
# 7. TRAIN MODEL
# --------------------------------------------------

print("\nTraining model...")

model.fit(X_train, y_train)

print("Training completed.")


# --------------------------------------------------
# 8. TEST MODEL
# --------------------------------------------------

predictions = model.predict(X_test)

accuracy = accuracy_score(y_test, predictions)

print("\nModel Accuracy:")
print(f"{accuracy * 100:.2f}%")

print("\nClassification Report:")
print(classification_report(y_test, predictions))


# --------------------------------------------------
# 9. SAVE MODEL
# --------------------------------------------------

joblib.dump(model, "triage_model.pkl")

print("\n----------------------------------------")
print("triage_model.pkl created successfully!")
print("----------------------------------------")