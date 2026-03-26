package com.smartfreight.invoice.controller;

import com.smartfreight.common.dto.ApiResponse;
import com.smartfreight.common.dto.PagedResponse;
import com.smartfreight.invoice.controller.dto.InvoiceDto;
import com.smartfreight.invoice.controller.dto.ReceiveInvoiceRequest;
import com.smartfreight.invoice.domain.InvoiceStatus;
import com.smartfreight.invoice.service.InvoiceService;
import com.smartfreight.observability.filter.CorrelationIdFilter;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/invoices")
@RequiredArgsConstructor
public class InvoiceController {

    private final InvoiceService invoiceService;

    @PostMapping
    public ResponseEntity<ApiResponse<InvoiceDto>> receiveInvoice(@Valid @RequestBody ReceiveInvoiceRequest req) {
        var invoice = invoiceService.receiveInvoice(req);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.ok(InvoiceDto.from(invoice), cid()));
    }

    @GetMapping("/{id}")
    public ApiResponse<InvoiceDto> getInvoice(@PathVariable String id) {
        return ApiResponse.ok(InvoiceDto.from(invoiceService.getById(id)), cid());
    }

    @GetMapping
    public ApiResponse<PagedResponse<InvoiceDto>> listInvoices(
            @RequestParam(required = false) InvoiceStatus status,
            @RequestParam(required = false) String carrierId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {

        var pageable = PageRequest.of(page, Math.min(size, 100), Sort.by(Sort.Direction.DESC, "createdAt"));
        Page<InvoiceDto> invoicePage;
        if (status != null) {
            invoicePage = invoiceService.listByStatus(status, pageable).map(InvoiceDto::from);
        } else if (carrierId != null) {
            invoicePage = invoiceService.listByCarrier(carrierId, pageable).map(InvoiceDto::from);
        } else {
            invoicePage = invoiceService.listAll(pageable).map(InvoiceDto::from);
        }
        return ApiResponse.ok(PagedResponse.from(invoicePage.getContent(), invoicePage.getNumber(), invoicePage.getSize(),
                                 invoicePage.getTotalElements(), invoicePage.getTotalPages(),
                                 invoicePage.isFirst(), invoicePage.isLast()), cid());
    }

    @GetMapping("/shipment/{shipmentId}")
    public ApiResponse<List<InvoiceDto>> getByShipment(@PathVariable String shipmentId) {
        var invoices = invoiceService.getByShipmentId(shipmentId).stream().map(InvoiceDto::from).toList();
        return ApiResponse.ok(invoices, cid());
    }

    @PostMapping("/{id}/match")
    public ApiResponse<InvoiceDto> triggerMatch(
            @PathVariable String id,
            @RequestParam(required = false) String shipmentId) {
        return ApiResponse.ok(InvoiceDto.from(invoiceService.runThreeWayMatch(id, shipmentId)), cid());
    }

    @PostMapping("/{id}/approve")
    public ApiResponse<InvoiceDto> manualApprove(
            @PathVariable String id,
            @AuthenticationPrincipal Jwt jwt) {
        String approvedBy = jwt != null ? jwt.getClaimAsString("email") : "system";
        return ApiResponse.ok(InvoiceDto.from(invoiceService.manualApprove(id, approvedBy)), cid());
    }

    @PostMapping("/{id}/mark-paid")
    public ApiResponse<InvoiceDto> markPaid(@PathVariable String id) {
        return ApiResponse.ok(InvoiceDto.from(invoiceService.markPaid(id)), cid());
    }

    @GetMapping("/overdue")
    public ApiResponse<List<InvoiceDto>> getOverdue() {
        var invoices = invoiceService.getOverdueInvoices().stream().map(InvoiceDto::from).toList();
        return ApiResponse.ok(invoices, cid());
    }

    private String cid() {
        return CorrelationIdFilter.getCurrentCorrelationId();
    }
}
