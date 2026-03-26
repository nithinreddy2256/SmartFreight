package com.smartfreight.shipment.controller;

import com.smartfreight.common.dto.ApiResponse;
import com.smartfreight.common.dto.PagedResponse;
import com.smartfreight.observability.filter.CorrelationIdFilter;
import com.smartfreight.shipment.controller.dto.AssignCarrierRequest;
import com.smartfreight.shipment.controller.dto.CreateShipmentRequest;
import com.smartfreight.shipment.controller.dto.ShipmentDto;
import com.smartfreight.shipment.controller.dto.UpdateStatusRequest;
import com.smartfreight.shipment.domain.ShipmentStatus;
import com.smartfreight.shipment.service.ShipmentService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;

/**
 * REST controller for shipment operations.
 *
 * <p>All endpoints return {@link ApiResponse} wrappers with the correlationId
 * header value included for client-side log correlation.
 *
 * <p>Authentication: JWT from Cognito (validated by Spring Security OAuth2 resource server).
 * Authorization: scopes defined in SecurityConfig (shippers see own shipments, admins see all).
 */
@RestController
@RequestMapping("/api/shipments")
@RequiredArgsConstructor
@Tag(name = "Shipments", description = "Shipment lifecycle management")
public class ShipmentController {

    private final ShipmentService shipmentService;

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Create a new shipment",
               description = "Creates a shipment record and publishes ShipmentCreatedEvent")
    public ResponseEntity<ApiResponse<ShipmentDto>> createShipment(
            @Valid @RequestBody CreateShipmentRequest request) {
        var result = shipmentService.createShipment(request);
        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(ApiResponse.ok(result, CorrelationIdFilter.getCurrentCorrelationId()));
    }

    @GetMapping("/{id}")
    @Operation(summary = "Get shipment by ID")
    public ApiResponse<ShipmentDto> getShipment(@PathVariable String id) {
        return ApiResponse.ok(
                shipmentService.getShipment(id),
                CorrelationIdFilter.getCurrentCorrelationId());
    }

    @GetMapping
    @Operation(summary = "Search and list shipments",
               description = "Paginated search with optional filters")
    public ApiResponse<PagedResponse<ShipmentDto>> listShipments(
            @RequestParam(required = false) String shipperId,
            @RequestParam(required = false) String carrierId,
            @RequestParam(required = false) ShipmentStatus status,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant fromDate,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant toDate,
            @RequestParam(required = false) String originCity,
            @RequestParam(required = false) String destinationCity,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        var pageable = PageRequest.of(page, Math.min(size, 100),
                Sort.by(Sort.Direction.DESC, "createdAt"));
        var result = shipmentService.searchShipments(
                shipperId, carrierId, status, fromDate, toDate,
                originCity, destinationCity, pageable);
        return ApiResponse.ok(
                PagedResponse.from(result.getContent(), result.getNumber(), result.getSize(),
                                 result.getTotalElements(), result.getTotalPages(),
                                 result.isFirst(), result.isLast()),
                CorrelationIdFilter.getCurrentCorrelationId());
    }

    @PutMapping("/{id}/status")
    @Operation(summary = "Update shipment status",
               description = "Transitions shipment to new status (validates state machine)")
    public ApiResponse<ShipmentDto> updateStatus(
            @PathVariable String id,
            @Valid @RequestBody UpdateStatusRequest request) {
        return ApiResponse.ok(
                shipmentService.updateStatus(id, request),
                CorrelationIdFilter.getCurrentCorrelationId());
    }

    @PostMapping("/{id}/assign-carrier")
    @Operation(summary = "Assign a carrier to the shipment")
    public ApiResponse<ShipmentDto> assignCarrier(
            @PathVariable String id,
            @Valid @RequestBody AssignCarrierRequest request) {
        return ApiResponse.ok(
                shipmentService.assignCarrier(id, request.getCarrierId(),
                        request.getCarrierName(), request.getRateId()),
                CorrelationIdFilter.getCurrentCorrelationId());
    }
}
