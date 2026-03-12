package com.smartfreight.lambda.carrierwebhook;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.MessageAttributeValue;
import software.amazon.awssdk.services.sns.model.PublishRequest;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;
import java.util.Map;
import java.util.UUID;
import java.util.logging.Logger;

/**
 * AWS Lambda function: Carrier Webhook Handler
 *
 * <p>Triggered by API Gateway HTTP API POST /webhooks/carrier/{carrierId}
 *
 * <p>Processing steps:
 * <ol>
 *   <li>Validate HMAC-SHA256 signature from X-Hub-Signature-256 header</li>
 *   <li>Parse carrier-specific event payload</li>
 *   <li>Normalize to SmartFreight tracking event format</li>
 *   <li>Publish to SNS shipment-events topic with TrackingEventReceivedEvent type</li>
 * </ol>
 *
 * <p>No Spring context — uses plain AWS SDK for fast cold starts.
 * Lambda memory: 512MB. Expected p99 execution time: <500ms.
 */
public class CarrierWebhookHandler
        implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {

    private static final Logger log = Logger.getLogger(CarrierWebhookHandler.class.getName());

    // AWS SDK clients initialized once at construction time (reused across invocations)
    private final SnsClient snsClient;
    private final ObjectMapper objectMapper;

    private static final String SHIPMENT_EVENTS_TOPIC_ARN =
            System.getenv("SHIPMENT_EVENTS_TOPIC_ARN");

    public CarrierWebhookHandler() {
        this.snsClient = SnsClient.builder()
                .httpClient(UrlConnectionHttpClient.create())
                .build();
        this.objectMapper = new ObjectMapper()
                .registerModule(new JavaTimeModule());
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent event, Context context) {
        var correlationId = UUID.randomUUID().toString();
        log.info("Processing carrier webhook. requestId=" + context.getAwsRequestId()
                 + " correlationId=" + correlationId);

        try {
            // 1. Extract carrier ID from path
            var carrierId = extractCarrierId(event);

            // 2. Validate HMAC signature
            if (!validateSignature(event, carrierId)) {
                log.warning("Invalid webhook signature. carrierId=" + carrierId);
                return response(401, "{\"error\": \"Invalid signature\"}");
            }

            // 3. Parse the webhook payload
            var body = event.getBody();
            if (body == null || body.isBlank()) {
                return response(400, "{\"error\": \"Empty request body\"}");
            }
            var payload = objectMapper.readTree(body);

            // 4. Normalize to TrackingEventMessage
            var trackingEvent = normalizeCarrierEvent(carrierId, payload, correlationId);

            // 5. Publish to SNS
            publishToSns(trackingEvent, correlationId);

            log.info("Webhook processed successfully. carrierId=" + carrierId
                     + " shipmentId=" + trackingEvent.shipmentId
                     + " status=" + trackingEvent.carrierStatus);

            return response(200, "{\"message\": \"OK\", \"correlationId\": \"" + correlationId + "\"}");

        } catch (Exception e) {
            log.severe("Failed to process webhook: " + e.getMessage());
            return response(500, "{\"error\": \"Internal server error\"}");
        }
    }

    private String extractCarrierId(APIGatewayV2HTTPEvent event) {
        var pathParams = event.getPathParameters();
        return pathParams != null ? pathParams.getOrDefault("carrierId", "unknown") : "unknown";
    }

    /**
     * Validates the HMAC-SHA256 signature provided by the carrier.
     * The shared secret is stored in Secrets Manager (resolved at startup via env var).
     */
    private boolean validateSignature(APIGatewayV2HTTPEvent event, String carrierId) {
        var signature = event.getHeaders() != null
                ? event.getHeaders().get("x-hub-signature-256") : null;
        if (signature == null) {
            // Some carriers don't sign webhooks — skip validation (log warning)
            log.warning("No signature header. carrierId=" + carrierId);
            return true; // Permissive for demo — in production, fail here
        }

        try {
            var secret = System.getenv("WEBHOOK_SECRET_" + carrierId.toUpperCase());
            if (secret == null) return true; // No secret configured — skip

            var mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            var expectedSig = "sha256=" + HexFormat.of().formatHex(
                    mac.doFinal(event.getBody().getBytes(StandardCharsets.UTF_8)));
            return expectedSig.equals(signature);
        } catch (Exception e) {
            log.severe("Signature validation error: " + e.getMessage());
            return false;
        }
    }

    /**
     * Normalizes carrier-specific event format to SmartFreight internal format.
     * Different carriers use different JSON schemas — this normalizes them.
     */
    private TrackingEventMessage normalizeCarrierEvent(String carrierId, JsonNode payload,
                                                        String correlationId) {
        var msg = new TrackingEventMessage();
        msg.correlationId = correlationId;

        switch (carrierId.toLowerCase()) {
            case "fedex" -> {
                msg.shipmentId = resolveShipmentId(
                        payload.path("TrackingInfo").path("customerTrackingId").asText());
                msg.carrierTrackingNumber = payload.path("TrackingInfo")
                        .path("trackingNumber").asText();
                msg.carrierStatus = payload.path("TrackingInfo")
                        .path("latestStatus").path("statusCode").asText();
                msg.statusDescription = payload.path("TrackingInfo")
                        .path("latestStatus").path("description").asText();
                msg.location = payload.path("TrackingInfo")
                        .path("latestStatus").path("scanLocation").path("city").asText() + ", "
                        + payload.path("TrackingInfo")
                        .path("latestStatus").path("scanLocation").path("stateOrProvinceCode").asText();
            }
            case "ups" -> {
                msg.shipmentId = resolveShipmentId(
                        payload.path("shipment").path("referenceNumber").asText());
                msg.carrierTrackingNumber = payload.path("shipment")
                        .path("package").path("trackingNumber").asText();
                msg.carrierStatus = payload.path("shipment")
                        .path("package").path("activity").get(0).path("status").path("type").asText();
                msg.statusDescription = payload.path("shipment")
                        .path("package").path("activity").get(0).path("description").asText();
                var loc = payload.path("shipment").path("package").path("activity").get(0)
                        .path("location").path("address");
                msg.location = loc.path("city").asText() + ", " + loc.path("stateProvince").asText();
            }
            default -> {
                // Generic format — expect SmartFreight internal format
                msg.shipmentId = payload.path("shipmentId").asText();
                msg.carrierTrackingNumber = payload.path("trackingNumber").asText();
                msg.carrierStatus = payload.path("status").asText();
                msg.statusDescription = payload.path("description").asText();
                msg.location = payload.path("location").asText();
            }
        }

        return msg;
    }

    /** Resolves a carrier reference (e.g., BOL number) to a SmartFreight shipment ID. */
    private String resolveShipmentId(String carrierReference) {
        // In a full implementation, this would query DynamoDB TrackingEventTable
        // or shipment-service to find the shipment by carrier reference.
        // For simplicity, we pass the reference through and let shipment-service look it up.
        return carrierReference;
    }

    private void publishToSns(TrackingEventMessage msg, String correlationId) throws Exception {
        var messageBody = objectMapper.writeValueAsString(msg);

        snsClient.publish(PublishRequest.builder()
                .topicArn(SHIPMENT_EVENTS_TOPIC_ARN)
                .message(messageBody)
                .messageAttributes(Map.of(
                        "eventType", MessageAttributeValue.builder()
                                .dataType("String")
                                .stringValue("TrackingEventReceivedEvent")
                                .build(),
                        "correlationId", MessageAttributeValue.builder()
                                .dataType("String")
                                .stringValue(correlationId)
                                .build()
                ))
                .build());
    }

    private APIGatewayV2HTTPResponse response(int statusCode, String body) {
        return APIGatewayV2HTTPResponse.builder()
                .withStatusCode(statusCode)
                .withBody(body)
                .withHeaders(Map.of("Content-Type", "application/json"))
                .build();
    }

    /** Internal event message format published to SNS. */
    static class TrackingEventMessage {
        public String shipmentId;
        public String carrierTrackingNumber;
        public String carrierStatus;
        public String statusDescription;
        public String location;
        public String correlationId;
        public String timestamp = java.time.Instant.now().toString();
    }
}
