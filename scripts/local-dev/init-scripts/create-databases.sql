-- Create application databases and users for local development
-- Runs automatically when postgres container starts for the first time

-- Shipment service database
CREATE DATABASE shipment_db;
CREATE USER shipment_svc WITH PASSWORD 'localpassword';
GRANT ALL PRIVILEGES ON DATABASE shipment_db TO shipment_svc;
GRANT ALL PRIVILEGES ON DATABASE shipment_db TO smartfreight;

-- Invoice service database
CREATE DATABASE invoice_db;
CREATE USER invoice_svc WITH PASSWORD 'localpassword';
GRANT ALL PRIVILEGES ON DATABASE invoice_db TO invoice_svc;
GRANT ALL PRIVILEGES ON DATABASE invoice_db TO smartfreight;

-- Connect to shipment_db and grant schema privileges
\connect shipment_db
GRANT ALL ON SCHEMA public TO shipment_svc;
GRANT ALL ON SCHEMA public TO smartfreight;

-- Connect to invoice_db and grant schema privileges
\connect invoice_db
GRANT ALL ON SCHEMA public TO invoice_svc;
GRANT ALL ON SCHEMA public TO smartfreight;
