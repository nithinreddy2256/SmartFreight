package com.smartfreight.shipment.messaging;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.smartfreight.aws.messaging.MessageEnvelope;
import com.smartfreight.common.exceptions.ResourceNotFoundException;
import com.smartfreight.shipment.domain.ShipmentStatus;
import com.smartfreight.shipment.service.ShipmentService;
import io.awspring.cloud.sqs.annotation.SqsListener;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;

/**
 * SQS consumer for tracking events from carrier webhooks.
 *
 * <p>Message flow:
 * <ol>
 *   <li>Carrier calls API Gateway → Lambda carrier-webhook-handler</li>
 *   <li>Lambda publishes TrackingEventReceivedEvent to SNS shipment-events</li>
 *   <li>SNS delivers message to SQS shipment-inbound-queue</li>
 *   <li>This listener processes the SQS message</li>
 * </ol>
 *
 * <p>Idempotency: the shipment-service checks if the tracking event has already
 * been processed (by DynamoDB TrackingEventTable eventId TTL — deduplication
 * is handled at the DynamoDB write level with conditional expressions).
 *
 * <p>Error handling: Resilience4j retry is applied via SQS visibility timeout.
 * After 3 failed processing attempts, the message moves to the SQS DLQ.
 * CloudWatch alarm triggers alert-topic notification to the operations team.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class TrackingEventListener {

    private final ShipmentService shipmentService;
    private final ObjectMapper objectMapper;

    /**
     * Processes a tracking event message from the shipment-inbound-queue.
     * The queue name is resolved from application.yml at runtime.
     */
    @SqsListener("${aws.sqs.shipment-inbound-queue-url}")
    public void onTrackingEvent(String messageBody) {
        TrackingEventMessage event = null;
        try {
            // Messages from SNS are wrapped in an envelope; unwrap if needed
            event = parseMessage(messageBody);
            MDC.put("correlationId", event.getCorrelationId());
            MDC.put("shipmentId", event.getShipmentId());

            log.info("Processing tracking event. shipmentId={} status={} location={}",
                    event.getShipmentId(), event.getCarrierStatus(), event.getLocation());

            var newStatus = mapCarrierStatus(event.getCarrierStatus());
            if (newStatus != null) {
                var request = new com.smartfreight.shipment.controller.dto.UpdateStatusRequest();
                request.setStatus(newStatus.name());
                request.setStatusReason(event.getStatusDescription());
                request.setLocation(event.getLocation());

                try {
                    shipmentService.updateStatus(event.getShipmentId(), request);
                } catch (ResourceNotFoundException e) {
                    // Log and skip — shipment may belong to another system
                    log.warn("Received tracking event for unknown shipment: {}", event.getShipmentId());
                }
            } else {
                log.debug("Ignoring unmapped carrier status: {}", event.getCarrierStatus());
            }
        } catch (Exception e) {
            log.error("Failed to process tracking event. messageBody={}", messageBody, e);
            // Re-throw to let SQS retry (visibility timeout will make message reappear)
            throw new RuntimeException("Failed to process tracking event", e);
        } finally {
            MDC.remove("correlationId");
            MDC.remove("shipmentId");
        }
    }

    private TrackingEventMessage parseMessage(String messageBody) throws Exception {
        // Check if this is an SNS envelope
        if (messageBody.contains("\"Type\":\"Notification\"")) {
            var envelope = objectMapper.readValue(messageBody, MessageEnvelope.class);
            return objectMapper.readValue(envelope.getMessage(), TrackingEventMessage.class);
        }
        return objectMapper.readValue(messageBody, TrackingEventMessage.class);
    }

    /**
     * Maps carrier-specific status codes to SmartFreight ShipmentStatus.
     * Returns null for statuses that don't require a status update.
     */
    private ShipmentStatus mapCarrierStatus(String carrierStatus) {
        if (carrierStatus == null) return null;
        return switch (carrierStatus.toUpperCase()) {
            case "PICKED_UP", "PACKAGE_RECEIVED", "SHIPMENT_PICKED_UP" -> ShipmentStatus.PICKED_UP;
            case "IN_TRANSIT", "AT_FEDEX_FACILITY", "DEPARTED_FACILITY",
                 "IN_TRANSIT_TO_DESTINATION" -> ShipmentStatus.IN_TRANSIT;
            case "OUT_FOR_DELIVERY", "ON_FedEx_VEHICLE" -> ShipmentStatus.OUT_FOR_DELIVERY;
            case "DELIVERED", "PACKAGE_DELIVERED" -> ShipmentStatus.DELIVERED;
            case "DELIVERY_EXCEPTION", "EXCEPTION", "UNABLE_TO_DELIVER" -> ShipmentStatus.EXCEPTION;
            default -> null; // status update not needed for this event
        };
    }

    /** Internal POJO for tracking event messages from the carrier-webhook Lambda. */
    @lombok.Data
    public static class TrackingEventMessage {
        private String shipmentId;
        private String carrierTrackingNumber;
        private String carrierStatus;
        private String statusDescription;
        private String location;
        private String correlationId;
        private String timestamp;
    }
}
