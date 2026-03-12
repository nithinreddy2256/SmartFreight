package com.smartfreight.carrier;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cache.annotation.EnableCaching;

/**
 * SmartFreight Carrier Service
 *
 * <p>Manages:
 * <ul>
 *   <li>Carrier master data (FedEx, UPS, DHL, regional carriers)</li>
 *   <li>Rate cards per lane (DynamoDB CarrierRateTable)</li>
 *   <li>Multi-carrier rate quoting for shipment assignment</li>
 *   <li>Carrier capacity availability by date</li>
 *   <li>Carrier performance scorecards (on-time delivery, damage rates)</li>
 * </ul>
 *
 * <p>Architecture notes:
 * <ul>
 *   <li>DynamoDB is the primary data store (high-read, fixed access patterns)</li>
 *   <li>Caffeine cache (5-minute TTL) reduces DynamoDB read unit consumption by ~80%</li>
 *   <li>Rate card data is refreshed from carrier APIs by EventBridge-triggered Lambda</li>
 * </ul>
 */
@SpringBootApplication
@EnableCaching
public class CarrierServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(CarrierServiceApplication.class, args);
    }
}
