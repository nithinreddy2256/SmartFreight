package com.smartfreight.analytics;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;

/**
 * SmartFreight Analytics Service
 *
 * <p>ETL orchestration and freight analytics:
 * <ul>
 *   <li>Triggers AWS Glue ETL jobs (freight-spend-aggregator, carrier-performance-etl)</li>
 *   <li>Polls Glue job status and handles failures</li>
 *   <li>Serves freight spend reports via Amazon Athena queries on S3 Parquet data</li>
 *   <li>Provides carrier performance scorecards (on-time rate, damage rate, cost/lb)</li>
 *   <li>Consumes analytics-queue for real-time metric updates</li>
 * </ul>
 */
@SpringBootApplication
@EnableAsync
public class AnalyticsServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(AnalyticsServiceApplication.class, args);
    }
}
