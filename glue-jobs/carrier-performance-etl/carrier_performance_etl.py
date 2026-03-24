"""
SmartFreight — Carrier Performance ETL Glue Job
================================================
PySpark ETL job that computes carrier performance scorecards from shipment data.
Metrics: on-time delivery rate, damage rate, cost per lb, avg transit days.

Triggered by: EventBridge Scheduler (daily at 03:00 UTC, after freight-spend-aggregator)
Input:        Aurora PostgreSQL (shipment-db) via JDBC
Output:       S3 smartfreight-etl-processed-{env}/carrier-performance/date={date}/
Glue catalog: smartfreight_analytics.carrier_performance_metrics

Runtime: AWS Glue 4.0 (Spark 3.3 + Python 3.10)
DPU: 2 (dev/test), 4 (prod)
"""

import sys
import json
import boto3
from datetime import datetime, timedelta

from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F

# ─── Job Parameters ───────────────────────────────────────────────────────────
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'environment',
    'processed_bucket',
    'aurora_shipment_url',
    'aurora_invoice_url',
    'aurora_secret_id',
    'lookback_days',        # Number of days to compute rolling metrics (default: 30)
    'processing_date',      # Anchor date for lookback window (default: today)
    'glue_catalog_database',
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

processing_date = args.get('processing_date',
    datetime.utcnow().strftime('%Y-%m-%d'))
lookback_days = int(args.get('lookback_days', '30'))
window_start = (datetime.strptime(processing_date, '%Y-%m-%d')
                - timedelta(days=lookback_days)).strftime('%Y-%m-%d')

print(f"[carrier-performance-etl] Starting. date={processing_date} "
      f"window={window_start} to {processing_date} env={args['environment']}")

# ─── Credentials from Secrets Manager ────────────────────────────────────────
secrets_client = boto3.client('secretsmanager')
creds = json.loads(
    secrets_client.get_secret_value(SecretId=args['aurora_secret_id'])['SecretString']
)
db_user = creds['username']
db_pass = creds['password']

jdbc_opts = {
    "user": db_user,
    "password": db_pass,
    "driver": "org.postgresql.Driver",
    "fetchsize": "1000",
}

# ─── Read Shipments (rolling window) ─────────────────────────────────────────
shipments_df = spark.read \
    .format("jdbc") \
    .option("url", args['aurora_shipment_url']) \
    .option("dbtable", f"""(
        SELECT
            s.id AS shipment_id,
            s.carrier_id,
            s.carrier_name,
            s.origin_state,
            s.dest_state,
            s.weight_lbs,
            s.negotiated_rate,
            s.actual_delivery,
            s.estimated_delivery,
            CASE WHEN s.actual_delivery IS NOT NULL
                      AND s.actual_delivery::date <= s.estimated_delivery::date
                 THEN TRUE ELSE FALSE END AS on_time,
            CASE WHEN s.actual_delivery IS NOT NULL
                 THEN EXTRACT(DAY FROM s.actual_delivery - s.created_at)
                 ELSE NULL END AS transit_days_actual,
            EXTRACT(DAY FROM s.estimated_delivery - s.created_at) AS transit_days_committed,
            DATE(s.created_at) AS shipment_date
        FROM shipments s
        WHERE DATE(s.created_at) BETWEEN '{window_start}' AND '{processing_date}'
          AND s.status IN ('DELIVERED', 'IN_TRANSIT', 'OUT_FOR_DELIVERY')
    ) shipments_window""") \
    .options(**jdbc_opts) \
    .load()

# ─── Read Invoices for financial metrics ─────────────────────────────────────
invoices_df = spark.read \
    .format("jdbc") \
    .option("url", args['aurora_invoice_url']) \
    .option("dbtable", f"""(
        SELECT
            i.shipment_id,
            i.carrier_id,
            i.invoiced_amount,
            i.approved_amount,
            i.status AS invoice_status,
            i.dispute_reason,
            CASE WHEN i.status = 'DISPUTED' THEN TRUE ELSE FALSE END AS disputed,
            DATE(i.created_at) AS invoice_date
        FROM invoices i
        WHERE DATE(i.created_at) BETWEEN '{window_start}' AND '{processing_date}'
    ) invoices_window""") \
    .options(**jdbc_opts) \
    .load()

print(f"[carrier-performance-etl] Loaded {shipments_df.count()} shipments, "
      f"{invoices_df.count()} invoices")

# ─── Compute carrier-level shipment metrics ───────────────────────────────────
shipment_metrics = shipments_df.groupBy("carrier_id", "carrier_name").agg(
    F.count("shipment_id").alias("total_shipments"),
    F.sum(F.when(F.col("on_time") == True, 1).otherwise(0)).alias("on_time_deliveries"),
    F.avg("transit_days_actual").alias("avg_actual_transit_days"),
    F.avg("transit_days_committed").alias("avg_committed_transit_days"),
    F.sum("weight_lbs").alias("total_weight_lbs"),
    F.sum("negotiated_rate").alias("total_negotiated_cost"),
    F.avg("weight_lbs").alias("avg_shipment_weight_lbs"),
    F.countDistinct("origin_state", "dest_state").alias("distinct_lanes_served"),
)

# ─── Compute carrier-level invoice / financial metrics ────────────────────────
invoice_metrics = invoices_df.groupBy("carrier_id").agg(
    F.count("shipment_id").alias("total_invoices"),
    F.sum(F.when(F.col("disputed") == True, 1).otherwise(0)).alias("disputed_invoices"),
    F.sum("invoiced_amount").alias("total_invoiced_amount"),
    F.sum("approved_amount").alias("total_approved_amount"),
    F.avg("invoiced_amount").alias("avg_invoice_amount"),
)

# ─── Join and compute derived KPIs ────────────────────────────────────────────
performance_df = shipment_metrics.join(
    invoice_metrics,
    on="carrier_id",
    how="left"
).withColumn(
    "on_time_rate_pct",
    F.round(F.col("on_time_deliveries") / F.col("total_shipments") * 100, 2)
).withColumn(
    "dispute_rate_pct",
    F.when(F.col("total_invoices") > 0,
           F.round(F.col("disputed_invoices") / F.col("total_invoices") * 100, 2))
     .otherwise(F.lit(0.0))
).withColumn(
    "cost_per_lb",
    F.when(F.col("total_weight_lbs") > 0,
           F.round(F.col("total_approved_amount") / F.col("total_weight_lbs"), 4))
     .otherwise(F.lit(None))
).withColumn(
    "transit_days_variance",
    F.round(F.col("avg_actual_transit_days") - F.col("avg_committed_transit_days"), 1)
).withColumn(
    "overall_score",
    # Composite score (0–100): weighted average of on-time rate (60%) + invoice accuracy (40%)
    F.round(
        F.col("on_time_rate_pct") * 0.6
        + (100 - F.col("dispute_rate_pct")) * 0.4,
        1
    )
).withColumn(
    "processing_date", F.lit(processing_date)
).withColumn(
    "lookback_days", F.lit(lookback_days)
).withColumn(
    "window_start", F.lit(window_start)
)

# ─── Tier assignment based on overall score ───────────────────────────────────
performance_df = performance_df.withColumn(
    "carrier_tier",
    F.when(F.col("overall_score") >= 90, F.lit("PREFERRED"))
     .when(F.col("overall_score") >= 75, F.lit("STANDARD"))
     .when(F.col("overall_score") >= 60, F.lit("WATCH"))
     .otherwise(F.lit("REVIEW_REQUIRED"))
)

print(f"[carrier-performance-etl] Computed metrics for {performance_df.count()} carriers")

# ─── Write Parquet to S3 ─────────────────────────────────────────────────────
output_path = (f"s3://{args['processed_bucket']}/carrier-performance/"
               f"date={processing_date}/lookback={lookback_days}d/")

performance_df.write \
    .mode("overwrite") \
    .parquet(output_path)

print(f"[carrier-performance-etl] Written Parquet to {output_path}")

# ─── Update Glue Data Catalog partition ──────────────────────────────────────
glue_client = boto3.client('glue')
try:
    glue_client.batch_create_partition(
        DatabaseName=args['glue_catalog_database'],
        TableName='carrier_performance_metrics',
        PartitionInputList=[{
            'Values': [processing_date, str(lookback_days)],
            'StorageDescriptor': {
                'Location': output_path,
                'InputFormat': 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat',
                'OutputFormat': 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat',
                'SerdeInfo': {
                    'SerializationLibrary':
                        'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
                }
            }
        }]
    )
    print("[carrier-performance-etl] Updated Glue Data Catalog partition")
except glue_client.exceptions.AlreadyExistsException:
    # Partition already exists — update it instead
    glue_client.update_partition(
        DatabaseName=args['glue_catalog_database'],
        TableName='carrier_performance_metrics',
        PartitionValueList=[processing_date, str(lookback_days)],
        PartitionInput={
            'Values': [processing_date, str(lookback_days)],
            'StorageDescriptor': {
                'Location': output_path,
                'InputFormat': 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat',
                'OutputFormat': 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat',
                'SerdeInfo': {
                    'SerializationLibrary':
                        'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
                }
            }
        }
    )
    print("[carrier-performance-etl] Updated existing Glue Data Catalog partition")

print(f"[carrier-performance-etl] Completed successfully. date={processing_date}")
job.commit()
