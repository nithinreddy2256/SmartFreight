"""
SmartFreight — Freight Spend Aggregator Glue Job
=================================================
PySpark ETL job that reads daily shipment and invoice data from Aurora PostgreSQL,
aggregates freight spend by carrier, GL code, and lane, then writes Parquet output
to S3 for Athena queries.

Triggered by: EventBridge Scheduler (daily at 02:00 UTC)
Input:        Aurora PostgreSQL (shipment-db + invoice-db) via JDBC
Output:       S3 smartfreight-etl-processed-{env}/freight-spend/date={date}/
Glue catalog: smartfreight_analytics.freight_spend_daily

Runtime: AWS Glue 4.0 (Spark 3.3 + Python 3.10)
DPU: 2 (dev/test), 4 (prod)
"""

import sys
from datetime import datetime, timedelta
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import *

# ─── Job Parameters ───────────────────────────────────────────────────────────
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'environment',
    'processed_bucket',
    'aurora_shipment_url',
    'aurora_invoice_url',
    'aurora_secret_id',     # Secrets Manager secret ARN for DB credentials
    'processing_date',      # Date to process: YYYY-MM-DD (defaults to yesterday)
    'glue_catalog_database',
])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Resolve processing date (default: yesterday)
processing_date = args.get('processing_date',
    (datetime.utcnow() - timedelta(days=1)).strftime('%Y-%m-%d'))

print(f"[freight-spend-aggregator] Starting. date={processing_date} env={args['environment']}")

# ─── Read Credentials from Secrets Manager ────────────────────────────────────
import boto3
import json

secrets_client = boto3.client('secretsmanager')
secret_value = json.loads(
    secrets_client.get_secret_value(SecretId=args['aurora_secret_id'])['SecretString']
)
db_username = secret_value['username']
db_password = secret_value['password']

# ─── Read Shipments from Aurora ───────────────────────────────────────────────
shipments_df = spark.read \
    .format("jdbc") \
    .option("url", args['aurora_shipment_url']) \
    .option("dbtable", f"""(
        SELECT
            s.id AS shipment_id,
            s.reference_no,
            s.shipper_id,
            s.carrier_id,
            s.carrier_name,
            s.origin_state,
            s.dest_state,
            s.weight_lbs,
            s.negotiated_rate,
            s.gl_code,
            s.status,
            s.actual_delivery,
            s.estimated_delivery,
            CASE WHEN s.actual_delivery <= s.estimated_delivery THEN TRUE ELSE FALSE END AS on_time,
            DATE(s.created_at) AS shipment_date
        FROM shipments s
        WHERE DATE(s.created_at) = '{processing_date}'
          AND s.status = 'DELIVERED'
    ) shipments_subset""") \
    .option("user", db_username) \
    .option("password", db_password) \
    .option("driver", "org.postgresql.Driver") \
    .option("fetchsize", "1000") \
    .load()

# ─── Read Invoices from Aurora ────────────────────────────────────────────────
invoices_df = spark.read \
    .format("jdbc") \
    .option("url", args['aurora_invoice_url']) \
    .option("dbtable", f"""(
        SELECT
            i.id AS invoice_id,
            i.invoice_number,
            i.shipment_id,
            i.carrier_id,
            i.carrier_name,
            i.invoiced_amount,
            i.approved_amount,
            i.gl_code AS invoice_gl_code,
            i.status AS invoice_status,
            i.auto_approved,
            DATE(i.created_at) AS invoice_date
        FROM invoices i
        WHERE DATE(i.created_at) = '{processing_date}'
    ) invoices_subset""") \
    .option("user", db_username) \
    .option("password", db_password) \
    .option("driver", "org.postgresql.Driver") \
    .load()

print(f"[freight-spend-aggregator] Loaded {shipments_df.count()} shipments, "
      f"{invoices_df.count()} invoices")

# ─── Join Shipments and Invoices ──────────────────────────────────────────────
joined_df = shipments_df.join(
    invoices_df,
    shipments_df['shipment_id'] == invoices_df['shipment_id'],
    'left'
)

# ─── Aggregate Freight Spend by Carrier, Lane, GL Code ───────────────────────
aggregated_df = joined_df.groupBy(
    F.col("carrier_id"),
    F.col("carrier_name"),
    F.col("origin_state"),
    F.col("dest_state"),
    F.col("gl_code"),
    F.col("shipment_date")
).agg(
    F.count("shipment_id").alias("shipment_count"),
    F.sum("weight_lbs").alias("total_weight_lbs"),
    F.sum("negotiated_rate").alias("total_negotiated_rate"),
    F.sum("approved_amount").alias("total_invoiced_amount"),
    F.avg("weight_lbs").alias("avg_weight_lbs"),
    F.sum(F.when(F.col("on_time") == True, 1).otherwise(0)).alias("on_time_count"),
    F.sum(F.when(F.col("auto_approved") == True, 1).otherwise(0)).alias("auto_approved_count"),
    F.sum(F.when(F.col("invoice_status") == "DISPUTED", 1).otherwise(0)).alias("disputed_count")
).withColumn(
    "on_time_rate",
    F.col("on_time_count") / F.col("shipment_count")
).withColumn(
    "auto_approval_rate",
    F.col("auto_approved_count") / F.col("shipment_count")
).withColumn(
    "cost_per_lb",
    F.when(F.col("total_weight_lbs") > 0,
           F.col("total_invoiced_amount") / F.col("total_weight_lbs"))
    .otherwise(F.lit(None))
).withColumn(
    "lane_id",
    F.concat(F.col("origin_state"), F.lit("-"), F.col("dest_state"))
).withColumn(
    "processing_date", F.lit(processing_date)
)

print(f"[freight-spend-aggregator] Aggregated {aggregated_df.count()} rows")

# ─── Write to S3 as Parquet ───────────────────────────────────────────────────
output_path = f"s3://{args['processed_bucket']}/freight-spend/date={processing_date}/"

aggregated_df.write \
    .mode("overwrite") \
    .partitionBy("carrier_id") \
    .parquet(output_path)

print(f"[freight-spend-aggregator] Written Parquet output to {output_path}")

# ─── Update Glue Data Catalog ─────────────────────────────────────────────────
# Run MSCK REPAIR TABLE to update Athena partition metadata
glue_client = boto3.client('glue')
glue_client.batch_create_partition(
    DatabaseName=args['glue_catalog_database'],
    TableName='freight_spend_daily',
    PartitionInputList=[{
        'Values': [processing_date],
        'StorageDescriptor': {
            'Location': output_path,
            'InputFormat': 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat',
            'OutputFormat': 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat',
            'SerdeInfo': {
                'SerializationLibrary': 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
            }
        }
    }]
)

print(f"[freight-spend-aggregator] Completed successfully. date={processing_date}")
job.commit()
