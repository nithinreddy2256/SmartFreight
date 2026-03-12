-- V1: Create shipments table
-- SmartFreight Shipment Service — Aurora PostgreSQL

CREATE TABLE IF NOT EXISTS shipments (
    id                      VARCHAR(36)     NOT NULL,
    reference_no            VARCHAR(20)     NOT NULL UNIQUE,
    shipper_id              VARCHAR(36)     NOT NULL,
    shipper_name            VARCHAR(200)    NOT NULL,
    shipper_email           VARCHAR(255)    NOT NULL,
    consignee_id            VARCHAR(36),
    consignee_name          VARCHAR(200),
    consignee_email         VARCHAR(255),

    -- Origin address
    origin_street           VARCHAR(255),
    origin_city             VARCHAR(100)    NOT NULL,
    origin_state            VARCHAR(50)     NOT NULL,
    origin_zip              VARCHAR(20),
    origin_country          VARCHAR(2)      NOT NULL DEFAULT 'US',

    -- Destination address
    dest_street             VARCHAR(255),
    dest_city               VARCHAR(100)    NOT NULL,
    dest_state              VARCHAR(50)     NOT NULL,
    dest_zip                VARCHAR(20),
    dest_country            VARCHAR(2)      NOT NULL DEFAULT 'US',

    -- Carrier assignment
    carrier_id              VARCHAR(36),
    carrier_name            VARCHAR(200),
    carrier_tracking_number VARCHAR(100),
    carrier_rate_id         VARCHAR(36),
    negotiated_rate         DECIMAL(10,2),

    -- Freight details
    weight_lbs              DECIMAL(10,2),
    declared_value          DECIMAL(12,2),
    currency                VARCHAR(3)      NOT NULL DEFAULT 'USD',
    special_instructions    TEXT,
    gl_code                 VARCHAR(20),

    -- Status and timeline
    status                  VARCHAR(30)     NOT NULL DEFAULT 'CREATED',
    estimated_delivery      TIMESTAMP WITH TIME ZONE,
    actual_delivery         TIMESTAMP WITH TIME ZONE,
    pod_document_key        VARCHAR(500),
    recipient_name          VARCHAR(200),

    -- Audit
    created_at              TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_by              VARCHAR(36),
    version                 BIGINT          NOT NULL DEFAULT 0,

    CONSTRAINT pk_shipments PRIMARY KEY (id),
    CONSTRAINT chk_shipment_status CHECK (status IN (
        'CREATED', 'CARRIER_ASSIGNED', 'PICKED_UP', 'IN_TRANSIT',
        'OUT_FOR_DELIVERY', 'EXCEPTION', 'DELIVERED', 'CANCELLED'
    )),
    CONSTRAINT chk_weight_positive CHECK (weight_lbs IS NULL OR weight_lbs > 0),
    CONSTRAINT chk_declared_value_non_negative CHECK (declared_value IS NULL OR declared_value >= 0)
);

-- Performance indexes
CREATE INDEX idx_shipments_reference_no     ON shipments(reference_no);
CREATE INDEX idx_shipments_shipper_id       ON shipments(shipper_id);
CREATE INDEX idx_shipments_status           ON shipments(status);
CREATE INDEX idx_shipments_carrier_id       ON shipments(carrier_id);
CREATE INDEX idx_shipments_created_at       ON shipments(created_at DESC);
CREATE INDEX idx_shipments_estimated_deliv  ON shipments(estimated_delivery) WHERE estimated_delivery IS NOT NULL;
