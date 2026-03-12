-- V2: Create shipment_legs table for multi-leg routing

CREATE TABLE IF NOT EXISTS shipment_legs (
    id                  VARCHAR(36)     NOT NULL,
    shipment_id         VARCHAR(36)     NOT NULL,
    sequence            INT             NOT NULL,
    carrier_id          VARCHAR(36)     NOT NULL,
    carrier_name        VARCHAR(200),
    origin_city         VARCHAR(100)    NOT NULL,
    origin_state        VARCHAR(50)     NOT NULL,
    dest_city           VARCHAR(100)    NOT NULL,
    dest_state          VARCHAR(50)     NOT NULL,
    estimated_departure TIMESTAMP WITH TIME ZONE,
    actual_departure    TIMESTAMP WITH TIME ZONE,
    estimated_arrival   TIMESTAMP WITH TIME ZONE,
    actual_arrival      TIMESTAMP WITH TIME ZONE,
    status              VARCHAR(30)     NOT NULL DEFAULT 'CREATED',

    CONSTRAINT pk_shipment_legs PRIMARY KEY (id),
    CONSTRAINT fk_legs_shipment FOREIGN KEY (shipment_id)
        REFERENCES shipments(id) ON DELETE CASCADE,
    CONSTRAINT uq_legs_shipment_seq UNIQUE (shipment_id, sequence),
    CONSTRAINT chk_leg_status CHECK (status IN (
        'CREATED', 'CARRIER_ASSIGNED', 'PICKED_UP', 'IN_TRANSIT',
        'OUT_FOR_DELIVERY', 'EXCEPTION', 'DELIVERED', 'CANCELLED'
    ))
);

CREATE INDEX idx_legs_shipment_id ON shipment_legs(shipment_id);
CREATE INDEX idx_legs_carrier_id  ON shipment_legs(carrier_id);
