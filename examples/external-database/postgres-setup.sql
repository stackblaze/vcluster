-- PostgreSQL Database Setup for vCluster
-- Run this on your PostgreSQL server before deploying vCluster

-- Create user (replace 'your_password' with a secure password)
CREATE USER vcluster_user WITH PASSWORD 'your_password';

-- Create database
CREATE DATABASE vcluster_db OWNER vcluster_user;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE vcluster_db TO vcluster_user;

-- Connect to the database and grant schema privileges
\c vcluster_db
GRANT ALL ON SCHEMA public TO vcluster_user;

-- Verify setup
\du vcluster_user
\l vcluster_db

-- Optional: Create multiple databases for multiple vClusters
-- CREATE DATABASE vcluster_prod OWNER vcluster_user;
-- CREATE DATABASE vcluster_staging OWNER vcluster_user;
-- CREATE DATABASE vcluster_dev OWNER vcluster_user;
-- GRANT ALL PRIVILEGES ON DATABASE vcluster_prod TO vcluster_user;
-- GRANT ALL PRIVILEGES ON DATABASE vcluster_staging TO vcluster_user;
-- GRANT ALL PRIVILEGES ON DATABASE vcluster_dev TO vcluster_user;



