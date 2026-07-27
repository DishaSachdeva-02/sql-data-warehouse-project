/*
=================================================================================================
Quality Checks
=================================================================================================
Script Purpose:
      This script performs various quality checks for data consistency, accuracy,
      and standardization across the 'silver' schemas. It includes checks for: 
      - Null or duplicate primary keys.
      - Unwanted spaces in string fields.
      - Data standardization and consistency.
      - Invalid date ranges and orders.
      - Data consistency between related fields.
Usage Notes:
     - Run these checks after data loading Silver Layer.
     - Investigate and resolve any discrepancies found during the checks.
==================================================================================================
*/
-- ===============================================================================================
-- Checking crm_cust_info
-- ===============================================================================================
-- Check for nulls or duplicates in primary key
SELECT cst_id,COUNT(*) from bronze.crm_cust_info GROUP BY cst_id HAVING COUNT(*)>1;

-- Check for unwanted space in string values
SELECT * FROM bronze.crm_cust_info where cst_firstname!=TRIM(cst_firstname)

--Data Consistency and standardization
SELECT DISTINCT(cst_gndr) from bronze.crm_cust_info;


-- ===============================================================================================
-- Checking crm_prd_info
-- ===============================================================================================
--Check unique id duplication and req column creation
SELECT prd_id,COUNT(*) from bronze.crm_prd_info GROUP BY prd_id ;

--Checking trailing spaces in prd_nm
SELECT prd_nm from bronze.crm_prd_info where prd_nm !=TRIM(prd_nm);

--Checking for nulls or negative numbers
SELECT prd_cost from bronze.crm_prd_info where prd_cost<0 OR prd_cost IS Null;

--Data Standardization and consistency
SELECT prd_id,
prd_key,
REPLACE(SUBSTRING(prd_key,1,5),'-','_') AS cat_id,
SUBSTRING(prd_key,7,LEN(prd_key)) AS prd_key,
prd_nm,
ISNULL(prd_cost,0) AS prd_cost,
CASE UPPER(TRIM(prd_line))
     WHEN 'M' THEN 'Mountain'
     WHEN 'R' THEN 'Road'
     WHEN 'S' THEN 'Other Sales'
     WHEN 'T' THEN 'Touring'
     ELSE 'n/a'
END AS prd_line,
prd_start_dt,
prd_end_dt 
from bronze.crm_prd_info;

--Check for invalid date orders
SELECT * from bronze.crm_prd_info where prd_start_dt > prd_end_dt;

-- ===============================================================================================
-- Checking crm_sales_details
-- ===============================================================================================
--Check for trailing spaces in order number
SELECT sls_ord_num,
sls_prd_key,
sls_cust_id,
sls_order_dt,
sls_ship_dt,
sls_due_dt,
sls_sales,
sls_quantity,
sls_price
from bronze.crm_sales_details
WHERE sls_ord_num != TRIM(sls_ord_num);

--Check for invalid product keys (not existing in product master)
SELECT sls_ord_num,
sls_prd_key,
sls_cust_id,
sls_order_dt,
sls_ship_dt,
sls_due_dt,
sls_sales,
sls_quantity,
sls_price
from bronze.crm_sales_details
WHERE sls_prd_key NOT IN (SELECT prd_key from silver.crm_prd_info);

--Check for invalid customer IDs (not existing in customer master)
SELECT sls_ord_num,
sls_prd_key,
sls_cust_id,
sls_order_dt,
sls_ship_dt,
sls_due_dt,
sls_sales,
sls_quantity,
sls_price
from bronze.crm_sales_details
WHERE sls_cust_id NOT IN (SELECT cst_id from silver.crm_cust_info);

--Check for invalid or NULL order dates (zero, wrong length, or out of valid range)
SELECT 
NULLIF(sls_order_dt,0) sls_order_dt
from bronze.crm_sales_details
where sls_order_dt<=0 
OR LEN(sls_order_dt) !=8
OR sls_order_dt > 20500101
OR sls_order_dt < 19000101;

--Check for invalid or NULL ship dates (zero, wrong length, or out of valid range)
SELECT 
NULLIF(sls_ship_dt,0) sls_ship_dt
from bronze.crm_sales_details
where sls_ship_dt<=0 
OR LEN(sls_ship_dt) !=8
OR sls_ship_dt > 20500101
OR sls_ship_dt < 19000101;

--Check for invalid or NULL due dates (zero, wrong length, or out of valid range)
SELECT 
NULLIF(sls_due_dt,0) sls_due_dt
from bronze.crm_sales_details
where sls_due_dt<=0 
OR LEN(sls_due_dt) !=8
OR sls_due_dt > 20500101
OR sls_due_dt < 19000101;

--Check for logical date errors (order date after ship date or due date)
SELECT 
*
from bronze.crm_sales_details
where sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt;

--Check for data quality issues in sales metrics (mismatch in calculation, nulls, or negative values)
SELECT * 
from bronze.crm_sales_details
where sls_sales!=sls_quantity * sls_price 
OR sls_sales IS NULL 
OR sls_price IS NULL 
OR sls_quantity IS NULL
OR sls_sales <=0 
OR sls_price <=0
OR sls_quantity <=0;

-- ===============================================================================================
-- Checking erp_cust_az12
-- ===============================================================================================
--Check for trailing spaces or inconsistent formatting in customer ID
SELECT cid from bronze.erp_cust_az12 where cid != TRIM(cid);

--Check for invalid date formats or out of range birthdates
SELECT bdate from bronze.erp_cust_az12 
WHERE bdate > GETDATE() 
OR bdate < '1900-01-01'
OR bdate IS NULL
OR LEN(CAST(bdate AS VARCHAR)) != 10;

--Check for NULL or invalid gender values (non-standard entries)
SELECT gen, COUNT(*) as count 
from bronze.erp_cust_az12 
GROUP BY gen 
ORDER BY count DESC;

--Check for duplicate customer IDs in source
SELECT cid, COUNT(*) as duplicate_count 
from bronze.erp_cust_az12 
GROUP BY cid 
HAVING COUNT(*) > 1;

--Check for IDs that need cleaning (starting with 'NAS')
SELECT cid, SUBSTRING(cid,4,LEN(cid)) as cleaned_id 
from bronze.erp_cust_az12 
WHERE cid LIKE 'NAS%';

--Check for future birth dates that will be set to NULL
SELECT cid, bdate 
from bronze.erp_cust_az12 
WHERE bdate > GETDATE();

--Check for gender values that don't match standard categories
SELECT gen 
from bronze.erp_cust_az12 
WHERE UPPER(TRIM(gen)) NOT IN ('F','FEMALE','M','MALE','','NULL')
AND gen IS NOT NULL;

--Check for data completeness in all columns
SELECT 
COUNT(*) as total_records,
SUM(CASE WHEN cid IS NULL OR cid = '' THEN 1 ELSE 0 END) as null_empty_cid,
SUM(CASE WHEN bdate IS NULL THEN 1 ELSE 0 END) as null_bdate,
SUM(CASE WHEN gen IS NULL OR gen = '' THEN 1 ELSE 0 END) as null_empty_gen
FROM bronze.erp_cust_az12;

--Check for invalid birth dates that cannot be converted properly
SELECT cid, bdate 
from bronze.erp_cust_az12 
WHERE ISDATE(CAST(bdate AS VARCHAR)) = 0 
OR bdate < '1900-01-01';

--Check final data quality after transformation
SELECT 
COUNT(*) as total_records,
COUNT(DISTINCT cid) as unique_customers,
SUM(CASE WHEN bdate IS NULL THEN 1 ELSE 0 END) as null_birthdates,
SUM(CASE WHEN gen = 'n/a' THEN 1 ELSE 0 END) as unknown_gender
FROM silver.erp_cust_az12;

-- ===============================================================================================
-- Checking erp_loc_a101
-- ===============================================================================================
-- Data Standardization and Consistency
SELECT DISTINCT cntry FROM bronze.erp_loc_a101;

-- ===============================================================================================
-- Checking erp_px_cat_g1v2
-- ===============================================================================================
--Unwanted Spaces
SELECT * FROM bronze.erp_px_cat_g1v2
where subcat!=TRIM(subcat) 
OR cat!=TRIM(cat) 
OR maintenance!=TRIM(maintenance);
