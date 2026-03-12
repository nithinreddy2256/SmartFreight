package com.smartfreight.aws.messaging;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.smartfreight.common.events.BaseEvent;
import io.github.resilience4j.retry.annotation.Retry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.MessageAttributeValue;
import software.amazon.awssdk.services.sns.model.PublishRequest;

import java.util.Map;

/**
 * Publishes domain events to Amazon SNS topics.
 *
 * <p>Usage pattern in microservices:
 * <pre>
 * snsPublisher.publish(shipmentEventsTopicArn, deliveredEvent, correlationId);
 * </pre>
 *
 * <p>Each event is published with two SNS message attributes:
 * <ul>
 *   <li>{@code eventType} — used by SQS subscription filter policies to route
 *       only specific event types to specific queues. For example, notification-service's
 *       SQS subscription can filter to only receive ShipmentDeliveredEvent.</li>
 *   <li>{@code correlationId} — propagated for distributed tracing.</li>
 * </ul>
 *
 * <p>The {@code @Retry} annotation applies the "sns-publish" resilience4j retry policy
 * defined in application.yml — 3 attempts with exponential backoff (1s, 2s, 4s).
 * SnsException is the retryable exception; SdkClientException is not retried.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class SnsPublisher {

    private final SnsClient snsClient;
    private final ObjectMapper objectMapper;

    /**
     * Publishes an event to an SNS topic with correlation ID and event type attributes.
     *
     * @param topicArn     full ARN of the SNS topic
     * @param event        the domain event to publish (will be JSON-serialized)
     * @param correlationId MDC correlation ID for distributed tracing
     */
    @Retry(name = "sns-publish")
    public void publish(String topicArn, BaseEvent event, String correlationId) {
        String messageBody;
        try {
            messageBody = objectMapper.writeValueAsString(event);
        } catch (Exception e) {
            throw new MessageSerializationException(
                    "Failed to serialize event " + event.getClass().getSimpleName(), e);
        }

        var request = PublishRequest.builder()
                .topicArn(topicArn)
                .message(messageBody)
                .subject(event.getEventType())
                .messageAttributes(Map.of(
                        // Used for SQS filter policy routing
                        "eventType", MessageAttributeValue.builder()
                                .dataType("String")
                                .stringValue(event.getEventType())
                                .build(),
                        // Propagated for distributed tracing
                        "correlationId", MessageAttributeValue.builder()
                                .dataType("String")
                                .stringValue(correlationId != null ? correlationId : "unknown")
                                .build()
                ))
                .build();

        var response = snsClient.publish(request);

        log.info("Published event to SNS. topicArn={} eventType={} messageId={} correlationId={}",
                topicArn, event.getEventType(), response.messageId(), correlationId);
    }

    /**
     * Publishes a plain string message (for operational alerts to alert-topic).
     *
     * @param topicArn    full ARN of the SNS topic
     * @param subject     message subject (for email subscribers)
     * @param messageBody message body
     */
    @Retry(name = "sns-publish")
    public void publishAlert(String topicArn, String subject, String messageBody) {
        var request = PublishRequest.builder()
                .topicArn(topicArn)
                .subject(subject)
                .message(messageBody)
                .build();

        var response = snsClient.publish(request);
        log.info("Published alert to SNS. topicArn={} subject={} messageId={}",
                topicArn, subject, response.messageId());
    }

    /** Unchecked exception for serialization failures (non-retryable). */
    public static class MessageSerializationException extends RuntimeException {
        public MessageSerializationException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
