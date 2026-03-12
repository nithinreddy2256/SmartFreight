package com.smartfreight.shipment.repository;

import com.smartfreight.shipment.domain.Shipment;
import com.smartfreight.shipment.domain.ShipmentStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.Optional;

/**
 * Spring Data JPA repository for shipment persistence.
 *
 * <p>All methods query the Aurora PostgreSQL shipment-db.
 * The database connection is configured via Secrets Manager credentials
 * resolved at startup (see SecretsManagerConfig in aws-starter).
 */
@Repository
public interface ShipmentRepository extends JpaRepository<Shipment, String> {

    Optional<Shipment> findByReferenceNumber(String referenceNumber);

    /** Find all shipments for a specific shipper, newest first. */
    Page<Shipment> findByShipperIdOrderByCreatedAtDesc(String shipperId, Pageable pageable);

    /** Find all shipments in a given status (for bulk status updates and monitoring). */
    Page<Shipment> findByStatus(ShipmentStatus status, Pageable pageable);

    /** Find all shipments assigned to a carrier (for carrier performance queries). */
    Page<Shipment> findByCarrierId(String carrierId, Pageable pageable);

    /**
     * Search shipments by multiple optional filters. Used by the admin search API.
     * All parameters are optional — null values are ignored.
     */
    @Query("""
            SELECT s FROM Shipment s
            WHERE (:shipperId IS NULL OR s.shipperId = :shipperId)
              AND (:carrierId IS NULL OR s.carrierId = :carrierId)
              AND (:status IS NULL OR s.status = :status)
              AND (:fromDate IS NULL OR s.createdAt >= :fromDate)
              AND (:toDate IS NULL OR s.createdAt <= :toDate)
              AND (:originCity IS NULL OR LOWER(s.originCity) LIKE LOWER(CONCAT('%', :originCity, '%')))
              AND (:destinationCity IS NULL OR LOWER(s.destinationCity) LIKE LOWER(CONCAT('%', :destinationCity, '%')))
            ORDER BY s.createdAt DESC
            """)
    Page<Shipment> search(
            @Param("shipperId") String shipperId,
            @Param("carrierId") String carrierId,
            @Param("status") ShipmentStatus status,
            @Param("fromDate") Instant fromDate,
            @Param("toDate") Instant toDate,
            @Param("originCity") String originCity,
            @Param("destinationCity") String destinationCity,
            Pageable pageable);

    /**
     * Find shipments in-transit for more than 5 days (operational alert query).
     * Used by EventBridge-triggered sweep jobs.
     */
    @Query("""
            SELECT s FROM Shipment s
            WHERE s.status IN ('IN_TRANSIT', 'OUT_FOR_DELIVERY')
              AND s.estimatedDelivery < :thresholdDate
            """)
    Page<Shipment> findOverdueShipments(@Param("thresholdDate") Instant thresholdDate,
                                        Pageable pageable);

    /** Weekly shipment count summary by status (for analytics). */
    @Query("""
            SELECT s.status, COUNT(s) FROM Shipment s
            WHERE s.createdAt >= :fromDate
            GROUP BY s.status
            """)
    java.util.List<Object[]> countByStatusSince(@Param("fromDate") Instant fromDate);
}
