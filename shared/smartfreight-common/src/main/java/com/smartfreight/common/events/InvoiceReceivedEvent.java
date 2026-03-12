package com.smartfreight.common.events;

import com.fasterxml.jackson.annotation.JsonTypeName;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * Published by invoice-service when a new carrier invoice has been received
 * and saved (prior to OCR and 3-way match processing).
 */
@Getter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
@JsonTypeName("InvoiceReceivedEvent")
public class InvoiceReceivedEvent extends BaseEvent {

    private String invoiceId;
    private String carrierId;
    private String carrierName;
    private String invoiceNumber;
    private LocalDate invoiceDate;
    private BigDecimal invoiceAmount;
    private String currency;

    /** S3 object key of the uploaded invoice PDF. */
    private String documentKey;
}
