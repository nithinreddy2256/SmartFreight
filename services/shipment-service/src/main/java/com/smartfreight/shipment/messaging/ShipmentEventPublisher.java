package com.smartfreight.shipment.messaging;

import com.smartfreight.aws.messaging.SnsPublisher;
import com.smartfreight.common.events.*;
import com.smartfreight.shipment.domain.Shipment;
import com.smartfreight.shipment.domain.ShipmentStatus;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.Instant;
import java.time.temporal.ChronoUnit;

/**
 * Publishes shipment domain events to SNS after database transaction commits.
 *
 * <p>IMPORTANT: All event publications are registered as
 * {@link TransactionSynchronization#afterCommit()} callbacks. This ensures
 * events are NOT published if the database transaction rolls back, preventing
 * the classic dual-write problem.
 *
 * <p>Example flow:
 * <ol>
 *   <li>ShipmentService.updateStatus() → calls shipmentRepository.save() → DB write</li>
 *   <li>ShipmentService calls eventPublisher.publishStatusChanged()</li>
 *   <li>This method registers the SNS publish as an afterCommit callback</li>
 *   <li>Only after the DB commit succeeds does the SNS publish execute</li>
 * </ol>
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ShipmentEventPublisher {

    private final SnsPublisher snsPublisher;

    @Value("${aws.sns.shipment-events-topic-arn}")
    private String shipmentEventsTopicArn;

    public void publishShipmentCreated(Shipment shipment, String correlationId) {
        var event = ShipmentCreatedEvent.builder()
                .eventType("ShipmentCreatedEvent")
                .shipmentId(shipment.getId())
                .referenceNumber(shipment.getReferenceNumber())
                .shipperId(shipment.getShipperId())
                .shipperName(shipment.getShipperName())
                .shipperEmail(shipment.getShipperEmail())
                .consigneeId(shipment.getConsigneeId())
                .consigneeName(shipment.getConsigneeName())
                .consigneeEmail(shipment.getConsigneeEmail())
                .originCity(shipment.getOriginCity())
                .destinationCity(shipment.getDestinationCity())
                .carrierId(shipment.getCarrierId())
                .carrierName(shipment.getCarrierName())
                .estimatedDelivery(shipment.getEstimatedDelivery())
                .weightLbs(shipment.getWeightLbs() != null
                        ? shipment.getWeightLbs().doubleValue() : null)
                .declaredValue(shipment.getDeclaredValue() != null
                        ? shipment.getDeclaredValue().doubleValue() : null)
                .correlationId(correlationId)
                .source("shipment-service")
                .occurredAt(Instant.now())
                .schemaVersion(1)
                .build();

        publishAfterCommit(() -> snsPublisher.publish(shipmentEventsTopicArn, event, correlationId));
    }

    public void publishStatusChanged(Shipment shipment, ShipmentStatus oldStatus,
                                      ShipmentStatus newStatus, String reason,
                                      String location, String correlationId) {
        var event = ShipmentStatusChangedEvent.builder()
                .eventType("ShipmentStatusChangedEvent")
                .shipmentId(shipment.getId())
                .referenceNumber(shipment.getReferenceNumber())
                .oldStatus(oldStatus.name())
                .newStatus(newStatus.name())
                .statusReason(reason)
                .location(location)
                .shipperEmail(shipment.getShipperEmail())
                .consigneeEmail(shipment.getConsigneeEmail())
                .referenceDisplayName(shipment.getReferenceNumber())
                .correlationId(correlationId)
                .source("shipment-service")
                .occurredAt(Instant.now())
                .schemaVersion(1)
                .build();

        publishAfterCommit(() -> snsPublisher.publish(shipmentEventsTopicArn, event, correlationId));
    }

    public void publishShipmentDelivered(Shipment shipment, String correlationId) {
        var estimated = shipment.getEstimatedDelivery();
        var actual = shipment.getActualDelivery();
        boolean onTime = estimated != null && actual != null
                && !actual.isAfter(estimated);
        long daysVariance = (estimated != null && actual != null)
                ? ChronoUnit.DAYS.between(actual, estimated) : 0;

        var event = ShipmentDeliveredEvent.builder()
                .eventType("ShipmentDeliveredEvent")
                .shipmentId(shipment.getId())
                .referenceNumber(shipment.getReferenceNumber())
                .carrierId(shipment.getCarrierId())
                .carrierName(shipment.getCarrierName())
                .deliveredAt(actual)
                .onTime(onTime)
                .daysVariance((int) daysVariance)
                .podDocumentKey(shipment.getPodDocumentKey())
                .recipientName(shipment.getRecipientName())
                .shipperEmail(shipment.getShipperEmail())
                .consigneeEmail(shipment.getConsigneeEmail())
                .declaredValue(shipment.getDeclaredValue() != null
                        ? shipment.getDeclaredValue().doubleValue() : null)
                .correlationId(correlationId)
                .source("shipment-service")
                .occurredAt(Instant.now())
                .schemaVersion(1)
                .build();

        publishAfterCommit(() -> snsPublisher.publish(shipmentEventsTopicArn, event, correlationId));
    }

    public void publishCarrierAssigned(Shipment shipment, String correlationId) {
        var event = CarrierAssignedEvent.builder()
                .eventType("CarrierAssignedEvent")
                .shipmentId(shipment.getId())
                .referenceNumber(shipment.getReferenceNumber())
                .carrierId(shipment.getCarrierId())
                .carrierName(shipment.getCarrierName())
                .rateId(shipment.getCarrierRateId())
                .correlationId(correlationId)
                .source("shipment-service")
                .occurredAt(Instant.now())
                .schemaVersion(1)
                .build();

        publishAfterCommit(() -> snsPublisher.publish(shipmentEventsTopicArn, event, correlationId));
    }

    /**
     * Registers an SNS publish to run after the current transaction commits.
     * If no active transaction, publishes immediately (useful in tests).
     */
    private void publishAfterCommit(Runnable publishAction) {
        if (TransactionSynchronizationManager.isActualTransactionActive()) {
            TransactionSynchronizationManager.registerSynchronization(
                    new TransactionSynchronization() {
                        @Override
                        public void afterCommit() {
                            try {
                                publishAction.run();
                            } catch (Exception e) {
                                log.error("Failed to publish SNS event after transaction commit", e);
                                // Don't re-throw — the DB transaction already committed.
                                // The DLQ and CloudWatch alarm will capture this failure.
                            }
                        }
                    });
        } else {
            publishAction.run();
        }
    }
}
