-- Databricks notebook source
-- =====================================================================
-- First EMI bounce: contracts whose FIRST EMI fell due between
-- 01-Apr-2025 and 31-Aug-2026, and whether that first EMI bounced.
--
-- Anchor = INSTALMENT_NO = 1 due date (not "first receipt", which is
-- what the original vw_bounce_contracts used).
-- Bounce sources:
--   Autofin  -> dc_fnmvt_* receipts + receipt voucher / cheque return tables
--   Finnone  -> finnone_silver.fct_receipt (Receipt_Status = 'B')
--   Pennant  -> no bounce source in the original notebook; DPD proxy only
-- A DPD-based proxy is computed for every contract as a cross-check.
-- =====================================================================

-- COMMAND ----------

-- 1. First-EMI population
CREATE OR REPLACE TEMP VIEW first_emi AS
SELECT DISTINCT
    TRIM(CONTRACT_NUMBER)          AS contract_number,
    CAST(INSTALMENT_DATE AS DATE)  AS first_emi_date,
    CASE WHEN LENGTH(TRIM(CONTRACT_NUMBER)) IN (7, 8, 9) THEN 'Autofin'
         WHEN LENGTH(TRIM(CONTRACT_NUMBER)) = 12         THEN 'Finnone'
         WHEN LENGTH(TRIM(CONTRACT_NUMBER)) = 14         THEN 'Pennant'
         ELSE 'Unknown'
    END AS src
FROM mmfsl_prod.fusion_silverplus.cc_instalment_structure
WHERE INSTALMENT_NO = 1
  AND CAST(INSTALMENT_DATE AS DATE) BETWEEN DATE'2025-04-01' AND DATE'2026-08-31';

-- Sanity check: make sure all three systems actually show up here
-- SELECT src, COUNT(*) FROM first_emi GROUP BY src;

-- COMMAND ----------

-- 2a. Autofin: receipt header_keys that are known to have bounced
CREATE OR REPLACE TEMP VIEW autofin_bounced_keys AS
SELECT header_key
FROM mmfsl_prod.autofin_silver.dc_receipt_voucher_details
WHERE realisation_ind = 'B'
UNION
SELECT header_key
FROM mmfsl_prod.autofin_silver.dc_cheque_return_voucher_dtls
UNION
SELECT RCPT_HEADER_KEY AS header_key
FROM mmfsl_prod.autofin_silver.dc_batch_chq_rtn_dtls
WHERE cra_status = 'A';

-- COMMAND ----------

-- 2b. Autofin: first-EMI presentations that bounced
-- NOTE: if document_date is stored as a string (e.g. '01-APR-2025'),
--       replace CAST(... AS DATE) with to_date(document_date, 'dd-MMM-yyyy').
CREATE OR REPLACE TEMP VIEW autofin_first_emi_bounce AS
SELECT DISTINCT f.contract_number
FROM (
    SELECT header_key, reference_number, reference_type, sequence_type, document_date
    FROM mmfsl_prod.autofin_silver.dc_fnmvt_details
    UNION ALL
    SELECT header_key, reference_number, reference_type, sequence_type, document_date
    FROM mmfsl_prod.autofin_silver.dc_fnmvt_history
) d
JOIN first_emi f
  ON TRIM(d.reference_number) = f.contract_number
 AND CAST(d.document_date AS DATE) = f.first_emi_date      -- same-day match, as in the original notebook
JOIN autofin_bounced_keys k
  ON d.header_key = k.header_key
WHERE f.src = 'Autofin'
  AND d.sequence_type = 'R'
  AND d.reference_type = 'CONTRACT'
  AND CAST(d.document_date AS DATE) BETWEEN DATE'2025-04-01' AND DATE'2026-08-31';

-- COMMAND ----------

-- 2c. Finnone: first-EMI presentations that bounced
CREATE OR REPLACE TEMP VIEW finnone_first_emi_bounce AS
SELECT
    f.contract_number,
    MIN(r.Return_Reason_Description) AS return_reason
FROM first_emi f
JOIN mmfsl_prod.finnone_silver.fct_receipt r
  ON f.contract_number = TRIM(r.LOAN_ACCOUNT_NUMBER)
 AND f.first_emi_date  = CAST(r.Transaction_Date AS DATE)
WHERE f.src = 'Finnone'
  AND r.Receipt_Status = 'B'
GROUP BY f.contract_number;

-- COMMAND ----------

-- 2d. DPD proxy (all systems): overdue shortly after the first EMI date.
-- DPD on the due date itself is often 0 by construction, so this looks
-- 1-5 days after; adjust the window to match how npa_days_entry is populated.
CREATE OR REPLACE TEMP VIEW dpd_first_emi AS
SELECT DISTINCT f.contract_number
FROM first_emi f
JOIN mmfsl_prod.fusion_silverplus.npa_days_entry n
  ON f.contract_number = TRIM(n.HPA_NO)
 AND CAST(n.REPORT_DATE AS DATE) BETWEEN date_add(f.first_emi_date, 1)
                                     AND date_add(f.first_emi_date, 5)
WHERE n.AGE_CNT_DPD > 0;

-- COMMAND ----------

-- 3. Contract-level output
CREATE OR REPLACE TEMP VIEW first_emi_bounce_detail AS
SELECT
    f.contract_number,
    f.src,
    f.first_emi_date,
    date_format(f.first_emi_date, 'yyyyMM')                                   AS emi_yyyymm,
    CONCAT('FY', RIGHT(CAST(YEAR(add_months(f.first_emi_date, 9)) AS STRING), 2)) AS fiscal_year,
    CONCAT('Q', QUARTER(add_months(f.first_emi_date, -3)))                    AS fiscal_quarter,
    CASE
        WHEN f.src = 'Autofin' THEN CASE WHEN a.contract_number IS NOT NULL THEN 'Y' ELSE 'N' END
        WHEN f.src = 'Finnone' THEN CASE WHEN fn.contract_number IS NOT NULL THEN 'Y' ELSE 'N' END
        ELSE 'NA'   -- no presentation-level bounce source for Pennant yet
    END                                                                       AS first_emi_bounce_flag,
    fn.return_reason,
    CASE WHEN dp.contract_number IS NOT NULL THEN 'Y' ELSE 'N' END            AS dpd_proxy_flag
FROM first_emi f
LEFT JOIN autofin_first_emi_bounce a  ON f.contract_number = a.contract_number
LEFT JOIN finnone_first_emi_bounce fn ON f.contract_number = fn.contract_number
LEFT JOIN dpd_first_emi            dp ON f.contract_number = dp.contract_number;

-- COMMAND ----------

-- 4. Monthly summary, Apr-25 to Aug-26
SELECT
    emi_yyyymm,
    fiscal_year,
    fiscal_quarter,
    src,
    COUNT(DISTINCT contract_number)                                                         AS first_emi_contracts,
    COUNT(DISTINCT CASE WHEN first_emi_bounce_flag = 'Y' THEN contract_number END)          AS first_emi_bounced,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN first_emi_bounce_flag = 'Y' THEN contract_number END)
          / NULLIF(COUNT(DISTINCT CASE WHEN first_emi_bounce_flag IN ('Y','N') THEN contract_number END), 0), 2)
                                                                                            AS bounce_rate_pct,
    COUNT(DISTINCT CASE WHEN dpd_proxy_flag = 'Y' THEN contract_number END)                 AS dpd_proxy_count
FROM first_emi_bounce_detail
GROUP BY emi_yyyymm, fiscal_year, fiscal_quarter, src
ORDER BY emi_yyyymm, src;
