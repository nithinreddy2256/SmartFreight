-- V3: Add auto-update trigger for updated_at timestamps

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER trigger_shipments_updated_at
    BEFORE UPDATE ON shipments
    FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column();
