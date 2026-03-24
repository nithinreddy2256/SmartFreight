package com.smartfreight.invoice.repository;

import com.smartfreight.invoice.domain.Invoice;
import com.smartfreight.invoice.domain.InvoiceStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;

public interface InvoiceRepository extends JpaRepository<Invoice, String> {

    Optional<Invoice> findByInvoiceNumber(String invoiceNumber);

    Page<Invoice> findByCarrierId(String carrierId, Pageable pageable);

    Page<Invoice> findByStatus(InvoiceStatus status, Pageable pageable);

    List<Invoice> findByShipmentId(String shipmentId);

    List<Invoice> findByTextractJobId(String textractJobId);

    @Query("SELECT i FROM Invoice i WHERE i.status = 'APPROVED' AND i.paymentDueDate <= :today AND i.paidAt IS NULL")
    List<Invoice> findOverdueInvoices(LocalDate today);
}
