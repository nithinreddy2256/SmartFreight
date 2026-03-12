package com.smartfreight.shipment.service;

import com.smartfreight.common.events.ShipmentCreatedEvent;
import com.smartfreight.common.events.ShipmentDeliveredEvent;
import com.smartfreight.common.events.ShipmentStatusChangedEvent;
import com.smartfreight.common.exceptions.ResourceNotFoundException;
import com.smartfreight.observability.filter.CorrelationIdFilter;
import com.smartfreight.shipment.controller.dto.CreateShipmentRequest;
import com.smartfreight.shipment.controller.dto.ShipmentDto;
import com.smartfreight.shipment.controller.dto.UpdateStatusRequest;
import com.smartfreight.shipment.domain.Shipment;
import com.smartfreight.shipment.domain.ShipmentStatus;
import com.smartfreight.shipment.messaging.ShipmentEventPublisher;
import com.smartfreight.shipment.repository.ShipmentRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Core business logic for shipment lifecycle management.
 *
 * <p>All public methods are transactional and publish domain events to SNS
 * after the database transaction commits (via TransactionSynchronizationManager
 * in the event publisher).
 *
 * <p>Metrics published to CloudWatch:
 * <ul>
 *   <li>{@code shipment.created.count} — total shipments created</li>
 *   <li>{@code shipment.status.change.count} — status transitions by old/new status</li>
 *   <li>{@code shipment.delivered.count} — deliveries by on-time flag</li>
 *   <li>{@code shipment.creation.duration} — time to create a shipment (ms)</li>
 * </ul>
 */
@Slf4j
@Service
public class ShipmentService {

    private final ShipmentRepository shipmentRepository;
    private final ShipmentEventPublisher eventPublisher;
    private final Counter shipmentCreatedCounter;
    private final Counter shipmentDeliveredCounter;
    private final Timer shipmentCreationTimer;

    /** Running sequence counter for reference number generation (per process). */
    private final AtomicLong referenceSequence = new AtomicLong(0);

    public ShipmentService(ShipmentRepository shipmentRepository,
                           ShipmentEventPublisher eventPublisher,
                           MeterRegistry meterRegistry) {
        this.shipmentRepository = shipmentRepository;
        this.eventPublisher = eventPublisher;
        this.shipmentCreatedCounter = Counter.builder("shipment.created.count")
                .description("Total shipments created")
                .register(meterRegistry);
        this.shipmentDeliveredCounter = Counter.builder("shipment.delivered.count")
                .description("Total shipments delivered")
                .tag("on_time", "unknown")
                .register(meterRegistry);
        this.shipmentCreationTimer = Timer.builder("shipment.creation.duration")
                .description("Time to create a shipment including validation")
                .register(meterRegistry);
    }

    /**
     * Creates a new shipment record and publishes ShipmentCreatedEvent to SNS.
     *
     * @param request validated creation request from REST controller
     * @return the created shipment DTO
     */
    @Transactional
    public ShipmentDto createShipment(CreateShipmentRequest request) {
        return shipmentCreationTimer.record(() -> {
            var shipment = Shipment.builder()
                    .referenceNumber(generateReferenceNumber())
                    .shipperId(request.getShipperId())
                    .shipperName(request.getShipperName())
                    .shipperEmail(request.getShipperEmail())
                    .consigneeId(request.getConsigneeId())
                    .consigneeName(request.getConsigneeName())
                    .consigneeEmail(request.getConsigneeEmail())
                    .originCity(request.getOriginCity())
                    .originState(request.getOriginState())
                    .originZip(request.getOriginZip())
                    .originStreet(request.getOriginStreet())
                    .destinationCity(request.getDestinationCity())
                    .destinationState(request.getDestinationState())
                    .destinationZip(request.getDestinationZip())
                    .destinationStreet(request.getDestinationStreet())
                    .weightLbs(request.getWeightLbs())
                    .declaredValue(request.getDeclaredValue())
                    .specialInstructions(request.getSpecialInstructions())
                    .glCode(request.getGlCode())
                    .build();

            var saved = shipmentRepository.save(shipment);
            shipmentCreatedCounter.increment();

            var correlationId = CorrelationIdFilter.getCurrentCorrelationId();
            eventPublisher.publishShipmentCreated(saved, correlationId);

            log.info("Shipment created. id={} referenceNumber={} shipper={}",
                    saved.getId(), saved.getReferenceNumber(), saved.getShipperId());

            return ShipmentDto.from(saved);
        });
    }

    /**
     * Retrieves a shipment by ID.
     *
     * @throws ResourceNotFoundException if not found
     */
    @Transactional(readOnly = true)
    public ShipmentDto getShipment(String shipmentId) {
        return ShipmentDto.from(findOrThrow(shipmentId));
    }

    /**
     * Updates the shipment status after validating the transition.
     * Publishes ShipmentStatusChangedEvent (or ShipmentDeliveredEvent on delivery).
     *
     * @throws ResourceNotFoundException if shipment not found
     * @throws com.smartfreight.common.exceptions.BusinessRuleViolationException if transition invalid
     */
    @Transactional
    public ShipmentDto updateStatus(String shipmentId, UpdateStatusRequest request) {
        var shipment = findOrThrow(shipmentId);
        var oldStatus = shipment.getStatus();
        var newStatus = ShipmentStatus.valueOf(request.getStatus());

        shipment.transitionTo(newStatus);

        if (newStatus == ShipmentStatus.DELIVERED) {
            shipment.setActualDelivery(Instant.now());
            shipment.setRecipientName(request.getRecipientName());
            shipment.setPodDocumentKey(request.getPodDocumentKey());
        }

        var saved = shipmentRepository.save(shipment);
        var correlationId = CorrelationIdFilter.getCurrentCorrelationId();

        if (newStatus == ShipmentStatus.DELIVERED) {
            eventPublisher.publishShipmentDelivered(saved, correlationId);
            var onTime = saved.getEstimatedDelivery() != null
                    && !Instant.now().isAfter(saved.getEstimatedDelivery());
            Counter.builder("shipment.delivered.count")
                    .tag("on_time", String.valueOf(onTime))
                    .register(io.micrometer.core.instrument.Metrics.globalRegistry)
                    .increment();
        } else {
            eventPublisher.publishStatusChanged(saved, oldStatus, newStatus,
                    request.getStatusReason(), request.getLocation(), correlationId);
        }

        log.info("Shipment status updated. id={} {} -> {}", shipmentId, oldStatus, newStatus);
        return ShipmentDto.from(saved);
    }

    /**
     * Assigns a carrier to a shipment and transitions to CARRIER_ASSIGNED.
     */
    @Transactional
    public ShipmentDto assignCarrier(String shipmentId, String carrierId,
                                     String carrierName, String rateId) {
        var shipment = findOrThrow(shipmentId);
        shipment.transitionTo(ShipmentStatus.CARRIER_ASSIGNED);
        shipment.setCarrierId(carrierId);
        shipment.setCarrierName(carrierName);
        shipment.setCarrierRateId(rateId);

        var saved = shipmentRepository.save(shipment);
        var correlationId = CorrelationIdFilter.getCurrentCorrelationId();
        eventPublisher.publishCarrierAssigned(saved, correlationId);

        log.info("Carrier assigned to shipment. shipmentId={} carrierId={}",
                shipmentId, carrierId);
        return ShipmentDto.from(saved);
    }

    /** Paginated search with optional filters. */
    @Transactional(readOnly = true)
    public Page<ShipmentDto> searchShipments(String shipperId, String carrierId,
                                              ShipmentStatus status, Instant fromDate,
                                              Instant toDate, String originCity,
                                              String destinationCity, Pageable pageable) {
        return shipmentRepository.search(shipperId, carrierId, status, fromDate,
                        toDate, originCity, destinationCity, pageable)
                .map(ShipmentDto::from);
    }

    private Shipment findOrThrow(String shipmentId) {
        return shipmentRepository.findById(shipmentId)
                .orElseThrow(() -> ResourceNotFoundException.shipment(shipmentId));
    }

    /**
     * Generates a unique human-readable reference number.
     * Format: SF-YYYYMMDD-XXXXXX where XXXXXX is a zero-padded sequence.
     * Example: SF-20240310-000042
     */
    @Value("${shipment.reference.prefix:SF}")
    private String referencePrefix;

    private String generateReferenceNumber() {
        var date = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyyMMdd"));
        var seq = referenceSequence.incrementAndGet();
        return String.format("%s-%s-%06d", referencePrefix, date, seq);
    }
}
