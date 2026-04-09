package com.smartfreight.analytics.controller;

import com.smartfreight.analytics.service.AthenaQueryService;
import com.smartfreight.analytics.service.GlueJobService;
import com.smartfreight.common.dto.ApiResponse;
import com.smartfreight.observability.filter.CorrelationIdFilter;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/analytics")
@RequiredArgsConstructor
public class AnalyticsController {

    private final GlueJobService glueJobService;
    private final AthenaQueryService athenaQueryService;

    // ─── Glue Job Management ──────────────────────────────────────────────────

    @PostMapping("/jobs/{jobName}/run")
    public ApiResponse<String> runGlueJob(
            @PathVariable String jobName,
            @RequestBody(required = false) Map<String, String> arguments) {
        var runId = glueJobService.startJobRun(jobName, arguments != null ? arguments : Map.of());
        return ApiResponse.ok(runId, cid());
    }

    @GetMapping("/jobs/{jobName}/runs/{runId}")
    public ApiResponse<GlueJobService.GlueJobStatus> getJobStatus(
            @PathVariable String jobName,
            @PathVariable String runId) {
        return ApiResponse.ok(glueJobService.getJobStatus(jobName, runId), cid());
    }

    @GetMapping("/jobs/{jobName}/runs")
    public ApiResponse<List<GlueJobService.GlueJobStatus>> getRecentRuns(
            @PathVariable String jobName,
            @RequestParam(defaultValue = "10") int maxResults) {
        return ApiResponse.ok(glueJobService.getRecentJobRuns(jobName, maxResults), cid());
    }

    // ─── Freight Spend Reports ────────────────────────────────────────────────

    @GetMapping("/reports/freight-spend")
    public ApiResponse<List<Map<String, String>>> freightSpendReport(
            @RequestParam(defaultValue = "30") int days,
            @RequestParam(required = false) String carrierId) {
        if (days < 1 || days > 365) {
            throw new IllegalArgumentException("days must be between 1 and 365");
        }
        String sql = carrierId != null
                ? String.format(
                  "SELECT carrier_id, carrier_name, gl_code, SUM(approved_amount) AS total_spend, COUNT(*) AS invoice_count " +
                  "FROM freight_spend_aggregated " +
                  "WHERE carrier_id = '%s' " +
                  "AND invoice_date >= current_date - interval '%d' day " +
                  "GROUP BY carrier_id, carrier_name, gl_code ORDER BY total_spend DESC",
                  carrierId.replaceAll("[^a-zA-Z0-9_-]", ""), days)
                : String.format(
                  "SELECT carrier_id, carrier_name, SUM(approved_amount) AS total_spend, COUNT(*) AS invoice_count " +
                  "FROM freight_spend_aggregated " +
                  "WHERE invoice_date >= current_date - interval '%d' day " +
                  "GROUP BY carrier_id, carrier_name ORDER BY total_spend DESC",
                  days);
        return ApiResponse.ok(athenaQueryService.executeQuery(sql), cid());
    }

    @GetMapping("/reports/carrier-performance")
    public ApiResponse<List<Map<String, String>>> carrierPerformanceReport(
            @RequestParam(defaultValue = "30") int days) {
        if (days < 1 || days > 365) {
            throw new IllegalArgumentException("days must be between 1 and 365");
        }
        String sql = String.format(
                "SELECT carrier_id, carrier_name, " +
                "ROUND(AVG(CASE WHEN on_time THEN 1.0 ELSE 0.0 END) * 100, 1) AS on_time_rate_pct, " +
                "COUNT(*) AS total_shipments, " +
                "ROUND(AVG(total_weight_lbs), 0) AS avg_weight_lbs " +
                "FROM carrier_performance_metrics " +
                "WHERE delivered_at >= current_date - interval '%d' day " +
                "GROUP BY carrier_id, carrier_name ORDER BY on_time_rate_pct DESC",
                days);
        return ApiResponse.ok(athenaQueryService.executeQuery(sql), cid());
    }

    private String cid() {
        return CorrelationIdFilter.getCurrentCorrelationId();
    }
}
