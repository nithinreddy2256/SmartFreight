package com.smartfreight.analytics.service;

import io.github.resilience4j.retry.annotation.Retry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.glue.GlueClient;
import software.amazon.awssdk.services.glue.model.*;

import java.time.Instant;
import java.util.Map;

/**
 * AWS Glue ETL job management service.
 *
 * <p>Glue jobs in SmartFreight:
 * <ul>
 *   <li>{@code freight-spend-aggregator} — PySpark job, reads Aurora via JDBC,
 *       outputs aggregated spend by GL code / carrier / lane as Parquet to S3</li>
 *   <li>{@code carrier-performance-etl} — Computes on-time delivery rate,
 *       damage rate, and cost/lb by carrier from shipment data</li>
 * </ul>
 *
 * <p>Triggered by:
 * <ul>
 *   <li>EventBridge Scheduler (nightly 02:00 UTC for freight-spend-aggregator)</li>
 *   <li>REST API (manual trigger via /api/analytics/jobs/{name}/run)</li>
 * </ul>
 *
 * <p>Retry strategy: Glue jobs are idempotent (they overwrite S3 output partitions),
 * so failures can be retried. The {@code @Retry} annotation handles transient AWS API errors.
 * Job-level failures (bad data) are not retried — alert-topic notification is sent.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class GlueJobService {

    private final GlueClient glueClient;

    /**
     * Starts a Glue ETL job run.
     *
     * @param jobName   Glue job name (must match the Terraform-provisioned name)
     * @param arguments runtime arguments passed to the PySpark job
     * @return Glue job run ID for status polling
     */
    @Retry(name = "glue-api")
    public String startJobRun(String jobName, Map<String, String> arguments) {
        var request = StartJobRunRequest.builder()
                .jobName(jobName)
                .arguments(arguments)
                .build();

        var response = glueClient.startJobRun(request);
        log.info("Started Glue job. jobName={} runId={}", jobName, response.jobRunId());
        return response.jobRunId();
    }

    /**
     * Gets the current status of a Glue job run.
     *
     * @return job run details including state (RUNNING, SUCCEEDED, FAILED, etc.)
     */
    @Retry(name = "glue-api")
    public GlueJobStatus getJobStatus(String jobName, String runId) {
        var request = GetJobRunRequest.builder()
                .jobName(jobName)
                .runId(runId)
                .build();

        var response = glueClient.getJobRun(request);
        var run = response.jobRun();

        return new GlueJobStatus(
                run.jobName(),
                run.id(),
                run.jobRunStateAsString(),
                run.startedOn(),
                run.completedOn(),
                run.executionTime(),
                run.errorMessage()
        );
    }

    /**
     * Lists recent job runs for a Glue job (for monitoring dashboard).
     */
    public java.util.List<GlueJobStatus> getRecentJobRuns(String jobName, int maxResults) {
        var request = GetJobRunsRequest.builder()
                .jobName(jobName)
                .maxResults(maxResults)
                .build();

        return glueClient.getJobRuns(request).jobRuns().stream()
                .map(run -> new GlueJobStatus(
                        run.jobName(), run.id(), run.jobRunStateAsString(),
                        run.startedOn(), run.completedOn(), run.executionTime(), run.errorMessage()))
                .toList();
    }

    public record GlueJobStatus(
            String jobName,
            String runId,
            String state,
            Instant startedAt,
            Instant completedAt,
            Integer executionTimeSeconds,
            String errorMessage
    ) {
        public boolean isRunning() {
            return "RUNNING".equals(state) || "STARTING".equals(state);
        }

        public boolean isSucceeded() {
            return "SUCCEEDED".equals(state);
        }

        public boolean isFailed() {
            return "FAILED".equals(state) || "ERROR".equals(state) || "TIMEOUT".equals(state);
        }
    }
}
