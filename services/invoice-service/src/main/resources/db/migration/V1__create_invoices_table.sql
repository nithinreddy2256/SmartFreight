-- V1: Create invoices table
CREATE TABLE invoices (
    id                       VARCHAR(36)    PRIMARY KEY,
    invoice_number           VARCHAR(100)   NOT NULL UNIQUE,
    carrier_id               VARCHAR(36)    NOT NULL,
    carrier_name             VARCHAR(200),
    shipment_id              VARCHAR(36),
    shipment_reference_number VARCHAR(20),
    invoice_date             DATE,
    invoiced_amount          NUMERIC(12, 2),
    expected_amount          NUMERIC(12, 2),
    approved_amount          NUMERIC(12, 2),
    currency                 VARCHAR(3)     NOT NULL DEFAULT 'USD',
    gl_code                  VARCHAR(20),
    status                   VARCHAR(30)    NOT NULL DEFAULT 'RECEIVED',
    document_key             VARCHAR(500),
    textract_job_id          VARCHAR(200),
    dispute_reason           VARCHAR(50),
    dispute_description      TEXT,
    payment_due_date         DATE,
    paid_at                  TIMESTAMPTZ,
    auto_approved            BOOLEAN        NOT NULL DEFAULT FALSE,
    approved_at              TIMESTAMPTZ,
    approved_by              VARCHAR(100),
    created_at               TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at               TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    version                  BIGINT         NOT NULL DEFAULT 0
);

CREATE INDEX idx_invoices_carrier_id   ON invoices (carrier_id);
CREATE INDEX idx_invoices_shipment_id  ON invoices (shipment_id);
CREATE INDEX idx_invoices_status       ON invoices (status);
CREATE INDEX idx_invoices_invoice_number ON invoices (invoice_number);
