-- MySQL Database Setup for vCluster
-- Run this on your MySQL server before deploying vCluster

-- Create database
CREATE DATABASE IF NOT EXISTS vcluster_db;

-- Create user (replace 'your_password' with a secure password)
CREATE USER IF NOT EXISTS 'vcluster_user'@'%' IDENTIFIED BY 'your_password';

-- Grant all privileges on the vCluster database
GRANT ALL PRIVILEGES ON vcluster_db.* TO 'vcluster_user'@'%';

-- Apply privileges
FLUSH PRIVILEGES;

-- Verify setup
SHOW GRANTS FOR 'vcluster_user'@'%';

-- Optional: Create multiple databases for multiple vClusters
-- CREATE DATABASE IF NOT EXISTS vcluster_prod;
-- CREATE DATABASE IF NOT EXISTS vcluster_staging;
-- CREATE DATABASE IF NOT EXISTS vcluster_dev;
-- GRANT ALL PRIVILEGES ON vcluster_prod.* TO 'vcluster_user'@'%';
-- GRANT ALL PRIVILEGES ON vcluster_staging.* TO 'vcluster_user'@'%';
-- GRANT ALL PRIVILEGES ON vcluster_dev.* TO 'vcluster_user'@'%';
-- FLUSH PRIVILEGES;



