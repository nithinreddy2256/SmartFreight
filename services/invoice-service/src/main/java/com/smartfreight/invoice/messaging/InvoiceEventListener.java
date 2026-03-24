package com.smartfreight.invoice.messaging;

import com.smartfreight.common.events.ShipmentDeliveredEvent;
import com.smartfreight.invoice.service.InvoiceService;
import io.awspring.cloud.sqs.annotation.SqsListener;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * Consumes events from the invoice-processing-queue.
 *
 * <p>ShipmentDeliveredEvent triggers 3-way match for any pending invoices
 * associated with that shipment.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class InvoiceEventListener {

    private final InvoiceService invoiceService;

    @SqsListener("${aws.sqs.invoice-processing-queue-url}")
    public void handleShipmentDelivered(ShipmentDeliveredEvent event) {
        log.info("Received ShipmentDeliveredEvent. shipmentId={} referenceNumber={}",
                event.getShipmentId(), event.getReferenceNumber());

        var pendingInvoices = invoiceService.getByShipmentId(event.getShipmentId());
        if (pendingInvoices.isEmpty()) {
            log.debug("No pending invoices for shipmentId={}", event.getShipmentId());
            return;
        }

        for (var invoice : pendingInvoices) {
            try {
                invoiceService.runThreeWayMatch(invoice.getId(), event.getShipmentId());
            } catch (Exception e) {
                log.error("3-way match failed. invoiceId={} shipmentId={} error={}",
                        invoice.getId(), event.getShipmentId(), e.getMessage(), e);
            }
        }
    }
}
