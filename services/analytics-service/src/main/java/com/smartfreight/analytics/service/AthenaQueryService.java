package com.smartfreight.analytics.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.athena.AthenaClient;
import software.amazon.awssdk.services.athena.model.*;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Runs ad-hoc Athena queries against the processed Parquet data in S3.
 *
 * <p>Athena queries the Glue Data Catalog tables created by the PySpark ETL jobs.
 * Results are written to an S3 output location and polled for completion.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class AthenaQueryService {

    private final AthenaClient athenaClient;

    @Value("${aws.athena.database:smartfreight_analytics}")
    private String database;

    @Value("${aws.athena.output-location}")
    private String outputLocation;

    private static final int POLL_INTERVAL_MS = 1000;
    private static final int MAX_POLL_ATTEMPTS = 60;

    /**
     * Executes a query and waits for results (synchronous, up to 60s).
     * Suitable for dashboard queries — use async for long ETL queries.
     *
     * @return list of rows, each a map of column_name → value
     */
    public List<Map<String, String>> executeQuery(String sql) {
        log.info("Executing Athena query. database={} sql={}", database, sql);

        var startRequest = StartQueryExecutionRequest.builder()
                .queryString(sql)
                .queryExecutionContext(QueryExecutionContext.builder().database(database).build())
                .resultConfiguration(ResultConfiguration.builder().outputLocation(outputLocation).build())
                .build();

        var startResponse = athenaClient.startQueryExecution(startRequest);
        var executionId = startResponse.queryExecutionId();
        log.info("Athena query started. executionId={}", executionId);

        waitForCompletion(executionId);
        return fetchResults(executionId);
    }

    private void waitForCompletion(String executionId) {
        for (int attempt = 0; attempt < MAX_POLL_ATTEMPTS; attempt++) {
            var status = athenaClient.getQueryExecution(
                    GetQueryExecutionRequest.builder().queryExecutionId(executionId).build())
                    .queryExecution().status();

            var state = status.state();
            if (state == QueryExecutionState.SUCCEEDED) {
                log.info("Athena query succeeded. executionId={}", executionId);
                return;
            }
            if (state == QueryExecutionState.FAILED || state == QueryExecutionState.CANCELLED) {
                throw new RuntimeException("Athena query failed. executionId=" + executionId
                        + " reason=" + status.stateChangeReason());
            }

            try {
                Thread.sleep(POLL_INTERVAL_MS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new RuntimeException("Interrupted waiting for Athena query", e);
            }
        }
        throw new RuntimeException("Athena query timed out after " + MAX_POLL_ATTEMPTS + "s. executionId=" + executionId);
    }

    private List<Map<String, String>> fetchResults(String executionId) {
        var request = GetQueryResultsRequest.builder().queryExecutionId(executionId).build();
        var response = athenaClient.getQueryResults(request);

        var rows = response.resultSet().rows();
        if (rows.isEmpty()) return List.of();

        // First row is column headers
        var headers = rows.get(0).data().stream()
                .map(Datum::varCharValue).toList();

        var results = new ArrayList<Map<String, String>>();
        for (int i = 1; i < rows.size(); i++) {
            var dataRow = rows.get(i).data();
            var map = new HashMap<String, String>();
            for (int j = 0; j < headers.size(); j++) {
                map.put(headers.get(j), j < dataRow.size() ? dataRow.get(j).varCharValue() : null);
            }
            results.add(map);
        }
        return results;
    }
}
