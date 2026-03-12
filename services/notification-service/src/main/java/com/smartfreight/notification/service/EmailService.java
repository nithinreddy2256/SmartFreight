package com.smartfreight.notification.service;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.thymeleaf.TemplateEngine;
import org.thymeleaf.context.Context;
import software.amazon.awssdk.services.sesv2.SesV2Client;
import software.amazon.awssdk.services.sesv2.model.*;

import java.util.List;
import java.util.Map;

/**
 * Core email sending service using Amazon SES v2.
 *
 * <p>Architecture:
 * <ul>
 *   <li>Templates are rendered by Thymeleaf with dynamic data from domain events</li>
 *   <li>Both HTML and plain-text versions are sent (multipart/alternative)</li>
 *   <li>All emails use the SES configuration set for bounce/complaint tracking</li>
 *   <li>SES Free Tier: 62,000 emails/month when sent from ECS (no charge)</li>
 * </ul>
 *
 * <p>Metrics published to CloudWatch:
 * <ul>
 *   <li>{@code email.sent.count} — tagged by template name</li>
 *   <li>{@code email.failure.count} — tagged by template name and error type</li>
 * </ul>
 */
@Slf4j
@Service
public class EmailService {

    private final SesV2Client sesClient;
    private final TemplateEngine templateEngine;
    private final Counter emailSentCounter;
    private final Counter emailFailureCounter;

    @Value("${aws.ses.from-address}")
    private String fromAddress;

    @Value("${aws.ses.configuration-set-name}")
    private String configurationSetName;

    @Value("${aws.ses.reply-to-address:noreply@smartfreight.com}")
    private String replyToAddress;

    public EmailService(SesV2Client sesClient,
                        TemplateEngine templateEngine,
                        MeterRegistry meterRegistry) {
        this.sesClient = sesClient;
        this.templateEngine = templateEngine;
        this.emailSentCounter = Counter.builder("email.sent.count")
                .description("Total emails sent successfully")
                .register(meterRegistry);
        this.emailFailureCounter = Counter.builder("email.failure.count")
                .description("Total email send failures")
                .register(meterRegistry);
    }

    /**
     * Sends an HTML email rendered from a Thymeleaf template.
     *
     * @param templateName  name of the template (without .html extension)
     * @param templateVars  variables available in the template
     * @param subject       email subject line
     * @param toAddresses   list of recipient email addresses
     */
    public void sendTemplatedEmail(String templateName, Map<String, Object> templateVars,
                                    String subject, List<String> toAddresses) {
        if (toAddresses == null || toAddresses.isEmpty()) {
            log.warn("No recipients specified for template: {}", templateName);
            return;
        }

        // Filter out null/blank addresses
        var validAddresses = toAddresses.stream()
                .filter(addr -> addr != null && !addr.isBlank())
                .toList();

        if (validAddresses.isEmpty()) {
            log.warn("All recipient addresses are blank for template: {}", templateName);
            return;
        }

        try {
            var context = new Context();
            templateVars.forEach(context::setVariable);

            // Render HTML body
            var htmlBody = templateEngine.process("email/" + templateName, context);

            // Render plain-text fallback
            var textBody = templateEngine.process("email/" + templateName + "-text", context);

            sendEmail(subject, htmlBody, textBody, validAddresses);

            emailSentCounter.increment();
            log.info("Email sent. template={} recipients={} subject={}",
                    templateName, validAddresses, subject);

        } catch (Exception e) {
            emailFailureCounter.increment();
            log.error("Failed to send email. template={} recipients={} error={}",
                    templateName, validAddresses, e.getMessage(), e);
            // Don't re-throw — email failures should not fail the SQS message processing.
            // The SES bounce/complaint rate metric will surface systematic failures.
        }
    }

    private void sendEmail(String subject, String htmlBody, String textBody,
                           List<String> toAddresses) {
        var destination = Destination.builder()
                .toAddresses(toAddresses)
                .build();

        var content = EmailContent.builder()
                .simple(Message.builder()
                        .subject(Content.builder()
                                .data(subject)
                                .charset("UTF-8")
                                .build())
                        .body(Body.builder()
                                .html(Content.builder()
                                        .data(htmlBody)
                                        .charset("UTF-8")
                                        .build())
                                .text(Content.builder()
                                        .data(textBody)
                                        .charset("UTF-8")
                                        .build())
                                .build())
                        .build())
                .build();

        var request = SendEmailRequest.builder()
                .fromEmailAddress(fromAddress)
                .replyToAddresses(replyToAddress)
                .destination(destination)
                .content(content)
                // Configuration set tracks bounces/complaints in CloudWatch
                .configurationSetName(configurationSetName)
                .build();

        sesClient.sendEmail(request);
    }
}
