package com.smartfreight.aws.messaging;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Getter;
import lombok.NoArgsConstructor;

/**
 * Represents the outer envelope of an SNS-to-SQS fanout message.
 *
 * <p>When SNS delivers a message to an SQS queue, it wraps the original
 * message body in an envelope. SQS consumers must unwrap this envelope
 * to get the actual event JSON.
 *
 * <p>Example envelope structure:
 * <pre>
 * {
 *   "Type": "Notification",
 *   "MessageId": "abc-123",
 *   "TopicArn": "arn:aws:sns:us-east-1:...:shipment-events",
 *   "Subject": "ShipmentDeliveredEvent",
 *   "Message": "{\"eventType\":\"ShipmentDeliveredEvent\", ...}",
 *   "MessageAttributes": {
 *     "eventType": { "Type": "String", "Value": "ShipmentDeliveredEvent" },
 *     "correlationId": { "Type": "String", "Value": "req-xyz-789" }
 *   }
 * }
 * </pre>
 *
 * <p>Note: When consuming messages sent directly to SQS (not via SNS fanout),
 * the message body is the raw event JSON without this envelope.
 */
@Getter
@NoArgsConstructor
public class MessageEnvelope {

    @JsonProperty("Type")
    private String type;

    @JsonProperty("MessageId")
    private String messageId;

    @JsonProperty("TopicArn")
    private String topicArn;

    @JsonProperty("Subject")
    private String subject;

    /** The actual event JSON — deserialize this to the specific event class. */
    @JsonProperty("Message")
    private String message;

    @JsonProperty("MessageAttributes")
    private java.util.Map<String, MessageAttribute> messageAttributes;

    public boolean isSnsEnvelope() {
        return "Notification".equals(type);
    }

    @Getter
    @NoArgsConstructor
    public static class MessageAttribute {
        @JsonProperty("Type")
        private String type;

        @JsonProperty("Value")
        private String value;
    }
}
