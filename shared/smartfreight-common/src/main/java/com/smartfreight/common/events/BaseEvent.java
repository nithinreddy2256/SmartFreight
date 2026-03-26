package com.smartfreight.common.events;

import com.fasterxml.jackson.annotation.JsonTypeInfo;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

import java.time.Instant;
import java.util.UUID;

/**
 * Base class for all SmartFreight domain events.
 *
 * <p>All events published to SNS extend this class. The {@code eventType} field
 * is used for SNS message attribute filtering — consumers can subscribe to
 * specific event types without receiving all events on the topic.
 *
 * <p>Serialized as JSON when published to SNS. The {@code correlationId} is
 * propagated from the originating HTTP request through the entire event chain,
 * enabling distributed tracing across services.
 *
 * <p>Example SNS message attribute filter policy (only receive ShipmentDeliveredEvent):
 * <pre>
 * {
 *   "eventType": ["ShipmentDeliveredEvent"]
 * }
 * </pre>
 */
@Getter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "eventType")
public abstract class BaseEvent {

    /**
     * Discriminator field used for SNS filter policies and deserialization.
     * Set automatically in each concrete event class via @JsonTypeName.
     */
    private String eventType;

    /**
     * Unique event identifier. Generated at event creation time.
     * Used for idempotency — consumers check this ID before processing
     * to avoid duplicate processing in at-least-once delivery scenarios.
     */
    private String eventId;

    /**
     * Event creation timestamp (UTC). Used for event ordering and
     * time-to-live calculations in downstream consumers.
     */
    private Instant occurredAt;

    /**
     * Propagated from MDC across service boundaries.
     * Enables end-to-end tracing: webhook → SNS → SQS → service → response.
     */
    private String correlationId;

    /**
     * Service that produced this event (e.g., "shipment-service", "carrier-webhook-lambda").
     */
    private String source;

    /**
     * Schema version for forward compatibility.
     * Increment when adding required fields. Consumers should handle
     * older versions gracefully.
     */
    private int schemaVersion;
}
