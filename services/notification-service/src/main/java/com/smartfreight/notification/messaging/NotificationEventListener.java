package com.smartfreight.notification.messaging;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.smartfreight.aws.messaging.MessageEnvelope;
import com.smartfreight.common.events.*;
import com.smartfreight.notification.service.EmailService;
import io.awspring.cloud.sqs.annotation.SqsListener;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * SQS consumer for all notification events.
 *
 * <p>This single listener handles ALL event types from the notification-queue.
 * The SNS filter policy on the subscription can be used to control which events
 * are delivered (e.g., only ShipmentDeliveredEvent and InvoiceDisputedEvent in prod).
 *
 * <p>Message routing:
 * <ol>
 *   <li>Deserialize the SQS message body (unwrap SNS envelope if present)</li>
 *   <li>Read the {@code eventType} field to determine which template to render</li>
 *   <li>Extract template variables from the specific event type</li>
 *   <li>Delegate to EmailService to render and send</li>
 * </ol>
 *
 * <p>Failure handling:
 * EmailService swallows send failures (logs them). This means a failure to send
 * one email does NOT cause the SQS message to be retried (preventing duplicate emails).
 * If there are systematic failures, they surface via the email.failure.count metric.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class NotificationEventListener {

    private final EmailService emailService;
    private final ObjectMapper objectMapper;

    @SqsListener("${aws.sqs.notification-queue-url}")
    public void onNotificationEvent(String messageBody) {
        String eventType = null;
        try {
            var rawJson = unwrapSnsEnvelope(messageBody);
            eventType = extractEventType(rawJson);
            MDC.put("eventType", eventType);

            log.info("Processing notification event. eventType={}", eventType);

            switch (eventType) {
                case "ShipmentCreatedEvent" -> {
                    var event = objectMapper.readValue(rawJson, ShipmentCreatedEvent.class);
                    MDC.put("correlationId", event.getCorrelationId());
                    handleShipmentCreated(event);
                }
                case "ShipmentStatusChangedEvent" -> {
                    var event = objectMapper.readValue(rawJson, ShipmentStatusChangedEvent.class);
                    MDC.put("correlationId", event.getCorrelationId());
                    handleShipmentStatusChanged(event);
                }
                case "ShipmentDeliveredEvent" -> {
                    var event = objectMapper.readValue(rawJson, ShipmentDeliveredEvent.class);
                    MDC.put("correlationId", event.getCorrelationId());
                    handleShipmentDelivered(event);
                }
                case "InvoiceApprovedEvent" -> {
                    var event = objectMapper.readValue(rawJson, InvoiceApprovedEvent.class);
                    MDC.put("correlationId", event.getCorrelationId());
                    handleInvoiceApproved(event);
                }
                case "InvoiceDisputedEvent" -> {
                    var event = objectMapper.readValue(rawJson, InvoiceDisputedEvent.class);
                    MDC.put("correlationId", event.getCorrelationId());
                    handleInvoiceDisputed(event);
                }
                case "CarrierRateUpdatedEvent" -> {
                    var event = objectMapper.readValue(rawJson, CarrierRateUpdatedEvent.class);
                    handleCarrierRateUpdated(event);
                }
                default -> log.debug("No notification handler for event type: {}", eventType);
            }
        } catch (Exception e) {
            log.error("Failed to process notification event. eventType={} error={}",
                    eventType, e.getMessage(), e);
            throw new RuntimeException("Failed to process notification event", e);
        } finally {
            MDC.remove("eventType");
            MDC.remove("correlationId");
        }
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────

    private void handleShipmentCreated(ShipmentCreatedEvent event) {
        Map<String, Object> vars = new HashMap<>();
        vars.put("shipmentId", event.getShipmentId());
        vars.put("referenceNumber", event.getReferenceNumber());
        vars.put("shipperName", event.getShipperName());
        vars.put("originCity", event.getOriginCity());
        vars.put("destinationCity", event.getDestinationCity());
        vars.put("carrierName", event.getCarrierName() != null ? event.getCarrierName() : "TBD");
        vars.put("estimatedDelivery", event.getEstimatedDelivery());
        vars.put("weightLbs", event.getWeightLbs());
        vars.put("trackingUrl", buildTrackingUrl(event.getShipmentId()));

        var recipients = List.of(event.getShipperEmail());
        emailService.sendTemplatedEmail(
                "shipment-created",
                vars,
                "Shipment " + event.getReferenceNumber() + " Created Successfully",
                recipients);
    }

    private void handleShipmentStatusChanged(ShipmentStatusChangedEvent event) {
        // Only send email for specific status transitions to avoid notification fatigue
        var newStatus = event.getNewStatus();
        if (!"IN_TRANSIT".equals(newStatus) && !"OUT_FOR_DELIVERY".equals(newStatus)) {
            return;
        }

        Map<String, Object> vars = new HashMap<>();
        vars.put("shipmentId", event.getShipmentId());
        vars.put("referenceNumber", event.getReferenceNumber());
        vars.put("newStatus", event.getNewStatus());
        vars.put("location", event.getLocation());
        vars.put("statusReason", event.getStatusReason());
        vars.put("trackingUrl", buildTrackingUrl(event.getShipmentId()));

        var recipients = new ArrayList<String>();
        if (event.getShipperEmail() != null) recipients.add(event.getShipperEmail());
        if (event.getConsigneeEmail() != null) recipients.add(event.getConsigneeEmail());

        var templateName = "IN_TRANSIT".equals(newStatus)
                ? "shipment-in-transit" : "shipment-out-for-delivery";
        var subject = "IN_TRANSIT".equals(newStatus)
                ? "Your Shipment " + event.getReferenceNumber() + " is In Transit"
                : "Your Shipment " + event.getReferenceNumber() + " is Out for Delivery Today!";

        emailService.sendTemplatedEmail(templateName, vars, subject, recipients);
    }

    private void handleShipmentDelivered(ShipmentDeliveredEvent event) {
        Map<String, Object> vars = new HashMap<>();
        vars.put("shipmentId", event.getShipmentId());
        vars.put("referenceNumber", event.getReferenceNumber());
        vars.put("carrierName", event.getCarrierName());
        vars.put("deliveredAt", event.getDeliveredAt());
        vars.put("deliveryLocation", event.getDeliveryLocation());
        vars.put("recipientName", event.getRecipientName());
        vars.put("onTime", event.isOnTime());
        vars.put("daysVariance", event.getDaysVariance());
        vars.put("trackingUrl", buildTrackingUrl(event.getShipmentId()));

        var recipients = new ArrayList<String>();
        if (event.getShipperEmail() != null) recipients.add(event.getShipperEmail());
        if (event.getConsigneeEmail() != null) recipients.add(event.getConsigneeEmail());

        emailService.sendTemplatedEmail(
                "shipment-delivered",
                vars,
                "Shipment " + event.getReferenceNumber() + " Delivered Successfully",
                recipients);
    }

    private void handleInvoiceApproved(InvoiceApprovedEvent event) {
        Map<String, Object> vars = new HashMap<>();
        vars.put("invoiceId", event.getInvoiceId());
        vars.put("invoiceNumber", event.getInvoiceNumber());
        vars.put("carrierName", event.getCarrierName());
        vars.put("shipmentReferenceNumber", event.getShipmentReferenceNumber());
        vars.put("approvedAmount", event.getApprovedAmount());
        vars.put("currency", event.getCurrency());
        vars.put("glCode", event.getGlCode());
        vars.put("paymentDueDate", event.getPaymentDueDate());
        vars.put("autoApproved", event.isAutoApproved());
        vars.put("invoiceUrl", buildInvoiceUrl(event.getInvoiceId()));

        emailService.sendTemplatedEmail(
                "invoice-approved",
                vars,
                "Invoice " + event.getInvoiceNumber() + " Approved for Payment",
                List.of(event.getApTeamEmail()));
    }

    private void handleInvoiceDisputed(InvoiceDisputedEvent event) {
        Map<String, Object> vars = new HashMap<>();
        vars.put("invoiceId", event.getInvoiceId());
        vars.put("invoiceNumber", event.getInvoiceNumber());
        vars.put("carrierName", event.getCarrierName());
        vars.put("shipmentReferenceNumber", event.getShipmentReferenceNumber());
        vars.put("invoicedAmount", event.getInvoicedAmount());
        vars.put("expectedAmount", event.getExpectedAmount());
        vars.put("discrepancyAmount", event.getDiscrepancyAmount());
        vars.put("discrepancyPercentage", Math.abs(event.getDiscrepancyPercentage()));
        vars.put("disputeReason", event.getDisputeReason());
        vars.put("disputeDescription", event.getDisputeDescription());
        vars.put("invoiceUrl", buildInvoiceUrl(event.getInvoiceId()));

        var recipients = new ArrayList<String>();
        if (event.getApTeamEmail() != null) recipients.add(event.getApTeamEmail());
        if (event.getCarrierRelationsEmail() != null) recipients.add(event.getCarrierRelationsEmail());

        emailService.sendTemplatedEmail(
                "invoice-disputed",
                vars,
                "ACTION REQUIRED: Invoice " + event.getInvoiceNumber() + " Disputed — "
                        + event.getDisputeReason(),
                recipients);
    }

    private void handleCarrierRateUpdated(CarrierRateUpdatedEvent event) {
        Map<String, Object> vars = new HashMap<>();
        vars.put("carrierName", event.getCarrierName());
        vars.put("laneId", event.getLaneId());
        vars.put("originRegion", event.getOriginRegion());
        vars.put("destinationRegion", event.getDestinationRegion());
        vars.put("previousRate", event.getPreviousRate());
        vars.put("newRate", event.getNewRate());
        vars.put("changePercentage", Math.abs(event.getChangePercentage()));
        vars.put("rateIncreased", event.getChangePercentage() > 0);
        vars.put("effectiveDate", event.getEffectiveDate());

        emailService.sendTemplatedEmail(
                "carrier-rate-updated",
                vars,
                "Carrier Rate Update: " + event.getCarrierName() + " — " + event.getLaneId(),
                List.of(event.getProcurementTeamEmail()));
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private String unwrapSnsEnvelope(String messageBody) throws Exception {
        if (messageBody.contains("\"Type\":\"Notification\"")) {
            var envelope = objectMapper.readValue(messageBody, MessageEnvelope.class);
            return envelope.getMessage();
        }
        return messageBody;
    }

    private String extractEventType(String json) throws Exception {
        var node = objectMapper.readTree(json);
        return node.path("eventType").asText();
    }

    @org.springframework.beans.factory.annotation.Value("${app.base-url:https://app.smartfreight.com}")
    private String appBaseUrl;

    private String buildTrackingUrl(String shipmentId) {
        return appBaseUrl + "/shipments/" + shipmentId + "/tracking";
    }

    private String buildInvoiceUrl(String invoiceId) {
        return appBaseUrl + "/invoices/" + invoiceId;
    }
}
