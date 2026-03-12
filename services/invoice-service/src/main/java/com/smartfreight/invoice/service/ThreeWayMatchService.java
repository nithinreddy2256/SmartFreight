package com.smartfreight.invoice.service;

import com.smartfreight.invoice.domain.Invoice;
import com.smartfreight.invoice.domain.InvoiceStatus;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;

/**
 * 3-way match service: compares carrier invoice against contracted rate × actual shipment weight.
 *
 * <p>3-way match logic:
 * <ol>
 *   <li>Find the shipment associated with this invoice (from shipment-service)</li>
 *   <li>Get the contracted rate for the carrier + lane (from carrier-service)</li>
 *   <li>Calculate expected amount = rate × actual weight × (1 + fuel surcharge)</li>
 *   <li>Compare invoiced amount vs. expected amount</li>
 *   <li>If difference within tolerance threshold ($5 or 2%, whichever is higher) → APPROVED</li>
 *   <li>If difference exceeds threshold → DISPUTED</li>
 * </ol>
 *
 * <p>This eliminates the need for manual AP review on matched invoices,
 * which typically represent 85-90% of carrier invoices.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ThreeWayMatchService {

    /** Maximum dollar discrepancy that auto-approves (e.g., rounding differences). */
    @Value("${invoice.match.dollar-tolerance:5.00}")
    private BigDecimal dollarTolerance;

    /** Maximum percentage discrepancy that auto-approves. */
    @Value("${invoice.match.percentage-tolerance:2.0}")
    private double percentageTolerance;

    /**
     * Runs the 3-way match for an invoice and sets its status accordingly.
     *
     * @param invoice       invoice with invoicedAmount and expectedAmount populated
     * @param shipmentFound whether the matching shipment was found
     * @return match result containing the outcome and reason
     */
    public MatchResult match(Invoice invoice, boolean shipmentFound) {
        if (!shipmentFound) {
            return new MatchResult(MatchOutcome.DISPUTED, "MISSING_REFERENCE",
                    "No matching shipment found for reference: " + invoice.getShipmentReferenceNumber());
        }

        if (invoice.getExpectedAmount() == null) {
            return new MatchResult(MatchOutcome.DISPUTED, "RATE_NOT_FOUND",
                    "Could not find contracted rate for carrier " + invoice.getCarrierId());
        }

        var invoiced = invoice.getInvoicedAmount();
        var expected = invoice.getExpectedAmount();
        var difference = invoiced.subtract(expected);
        var absDiff = difference.abs();

        // Check if within tolerance
        boolean withinDollarTolerance = absDiff.compareTo(dollarTolerance) <= 0;
        double percentageDiff = invoice.discrepancyPercentage();
        boolean withinPercentageTolerance = Math.abs(percentageDiff) <= percentageTolerance;

        if (withinDollarTolerance || withinPercentageTolerance) {
            // Minor difference — auto-approve
            invoice.setStatus(InvoiceStatus.APPROVED);
            invoice.setApprovedAmount(expected); // Pay expected, not invoiced
            invoice.setAutoApproved(true);

            log.info("Invoice auto-approved. invoiceId={} invoiced={} expected={} diff={}",
                    invoice.getId(), invoiced, expected, absDiff);
            return new MatchResult(MatchOutcome.APPROVED, null,
                    "Within tolerance (diff=$" + absDiff + ")");
        }

        // Significant discrepancy — dispute
        String reason = difference.compareTo(BigDecimal.ZERO) > 0 ? "OVERCHARGE" : "UNDERCHARGE";
        String description = String.format(
                "Invoice amount $%s differs from expected $%s by $%s (%.1f%%)",
                invoiced, expected, absDiff, Math.abs(percentageDiff));

        invoice.setStatus(InvoiceStatus.DISPUTED);
        invoice.setDisputeReason(reason);
        invoice.setDisputeDescription(description);

        log.warn("Invoice disputed. invoiceId={} reason={} invoiced={} expected={} diff={}",
                invoice.getId(), reason, invoiced, expected, absDiff);
        return new MatchResult(MatchOutcome.DISPUTED, reason, description);
    }

    public enum MatchOutcome { APPROVED, DISPUTED }

    public record MatchResult(MatchOutcome outcome, String reason, String description) {}
}
