-- V2: Create invoice_line_items table
CREATE TABLE invoice_line_items (
    id             VARCHAR(36)    PRIMARY KEY,
    invoice_id     VARCHAR(36)    NOT NULL REFERENCES invoices (id) ON DELETE CASCADE,
    description    VARCHAR(200)   NOT NULL,
    charge_type    VARCHAR(50),
    quantity       NUMERIC(10, 4),
    unit_price     NUMERIC(10, 4),
    total_amount   NUMERIC(12, 2) NOT NULL,
    gl_code        VARCHAR(20)
);

CREATE INDEX idx_line_items_invoice_id ON invoice_line_items (invoice_id);
