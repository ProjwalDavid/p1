-- Databricks notebook source
CREATE OR REPLACE temp view fnmvt as
select *
from mmfsl_prod.autofin_silver.dc_fnmvt_details
union
select *
from mmfsl_prod.autofin_silver.dc_fnmvt_history

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW vw_bounce_contracts AS

select d.*, g.* EXCEPT (header_key, TXN_ID, load_date, SRC_SYSTEM_NAME, SRC_TABLE_NAME)
from fnmvt d
,mmfsl_prod.autofin_silver.dc_receipt_voucher_details g
where sequence_type='R'
and d.header_key=g.header_key
and g.realisation_ind='B'
and d.reference_type='CONTRACT'
and exists (select 'x' from (select reference_number , min(header_key) header_key, min(document_date) document_date
from fnmvt f
where sequence_type='R'
-- and f.document_date > '01-APR-2025'
and reference_type='CONTRACT'
and  not exists (select 'X' From mmfsl_prod.autofin_silver.dc_fnmvt_reversal_link  where f.HEADER_KEY=SOURCE_HEADER_KEY)
 and  not exists (select 'X' From mmfsl_prod.autofin_silver.dc_cheque_return_voucher_dtls re where f.HEADER_KEY=re.header_key)
 and  not exists (select 'X' From mmfsl_prod.autofin_silver.dc_batch_chq_rtn_dtls where f.header_key = RCPT_HEADER_KEY and cra_status='A' )
group by reference_number) n
where d.header_key=n.header_key
);


-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW vw_first_emi_bounce_flag AS

SELECT DISTINCT
    a.NEW_HPANO,
    a.acct_yyyymm,

    CASE
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) >= 4
            THEN CONCAT(
                    'FY',
                    RIGHT(CAST(CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 1, 4) AS INT) + 1 AS STRING), 2)
                 )
        ELSE CONCAT(
                    'FY',
                    RIGHT(CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 1, 4) AS STRING), 2)
                 )
    END AS fiscal_year,

    CASE
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) BETWEEN 4 AND 6 THEN 'Q1'
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) BETWEEN 7 AND 9 THEN 'Q2'
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) BETWEEN 10 AND 12 THEN 'Q3'
        ELSE 'Q4'
    END AS fiscal_quarter,

    CASE
        WHEN b.reference_number IS NOT NULL THEN 'Y'
        ELSE 'N'
    END AS bounce_flag

FROM mmfsl_prod.fusion_monthly.dc202607 a
LEFT JOIN vw_bounce_contracts b
    ON TRIM(a.NEW_HPANO) = TRIM(b.reference_number)
WHERE a.acct_yyyymm BETWEEN 202204 AND 202603
  AND a.STATUS <> 'E';

-- COMMAND ----------

SELECT
    fiscal_year,
    fiscal_quarter,
    bounce_flag, acct_yyyymm,
    COUNT(DISTINCT NEW_HPANO) AS distinct_hpa_count
FROM vw_first_emi_bounce_flag
GROUP BY
    fiscal_year,
    fiscal_quarter,
    bounce_flag, acct_yyyymm
ORDER BY
    acct_yyyymm,
    fiscal_year,
    fiscal_quarter,
    bounce_flag;

-- COMMAND ----------

SELECT
    fiscal_quarter,
    bounce_flag, acct_yyyymm,
    COUNT(DISTINCT NEW_HPANO) AS distinct_hpa_count
FROM vw_first_emi_bounce_flag
GROUP BY
    fiscal_quarter,
    bounce_flag, acct_yyyymm
ORDER BY
    acct_yyyymm,
    fiscal_quarter,
    bounce_flag;

-- COMMAND ----------

create or replace table risk_analytics.M1 as
select distinct BATCH_NUMBER, LAST_MODIFIED_DATE, STATUS, CUSTOMER_REF_NO,MANDATE_GENERATION_DATE  from   ( SELECT distinct BATCH_NUMBER, LAST_MODIFIED_DATE, STATUS, CUSTOMER_REF_NO,MANDATE_GENERATION_DATE 
FROM fusion_silverplus.auto_cams_mandate_return
            UNION ALL             SELECT distinct BATCH_NUMBER, LAST_MODIFIED_DATE, STATUS, CUSTOMER_REF_NO  ,MANDATE_GENERATION_DATE          FROM mmfsl_prod.autofin_silver.auto_cams_mandate_return_bkp             UNION ALL
            SELECT distinct BATCH_NUMBER, LAST_MODIFIED_DATE, STATUS, CUSTOMER_REF_NO   ,MANDATE_GENERATION_DATE          FROM rbi_silver.auto_cams_mandate_return_h
            UNION ALL
            SELECT distinct BATCH_NUMBER, LAST_MODIFIED_DATE, STATUS, CUSTOMER_REF_NO ,MANDATE_GENERATION_DATE           FROM rbi_silver.auto_cams_mandate_return_n
            UNION ALL
            SELECT distinct BATCH_NUMBER, LAST_MODIFIED_DATE, STATUS, CUSTOMER_REF_NO ,MANDATE_GENERATION_DATE            FROM rbi_silver.auto_cams_mandate_return_test
) lack

-- COMMAND ----------

select count(*) from risk_analytics.xzmandate

-- COMMAND ----------

select count(*) from risk_analytics.xz

-- COMMAND ----------

SELECT 5035538 - 4984855

-- COMMAND ----------

create or replace temporary view axle as
select Unique_ID,
       `Loan_Account_#`,
       Transaction_Date,
       Author_Date,maker_date,
       STATUS,Creation_Date,
       case Mandate_Status
            when 50036.000000000000000000 then 'NOT INITIATED'
            when 50116.000000000000000000 then 'CLOSED'
            when 50115.000000000000000000 then 'BLOCKED'
            when 50038.000000000000000000 then 'COMPLETED'
            when 50037.000000000000000000 then 'INITIATED'
            when 50039.000000000000000000 then 'REJECTED'
            when 50117.000000000000000000 then 'UNBLOCKED'
            else null
       end as mandate_status ,
  case when to_date(Author_Date,'dd-MM-yyyy') is null then to_date(maker_date,'dd-MM-yyyy') else to_date(Author_Date,'dd-MM-yyyy') end as MANDATE_REQ_DATE1

 from FINNONE_SILVER.DIM_ECS_MANDATE_AD 
-- where Author_Date is null
-- where Unique_ID in (select c from mmfsl_prod.fusion_silverplus.ecs_batch_master)

--  limit 2
-- 1169938

-- COMMAND ----------

create or replace table risk_analytics.M2 as
    SELECT        
    BATCH_NUMBER,         CONTRACT_NUMBER,         BATCH_DATE AS MANDATE_REQ_DATE, txn_id, entry_type
    FROM    
    (         SELECT      BATCH_NUMBER, CONTRACT_NUMBER, BATCH_DATE      , txn_id, entry_type 
    FROM mmfsl_prod.fusion_silverplus.ecs_batch_master
        UNION ALL
    SELECT     BATCH_NUMBER, CONTRACT_NUMBER, BATCH_DATE, txn_id, entry_type
        FROM autofin_silver.ecs_batch_master_hist)

-- limit 2

-- COMMAND ----------

create or replace table risk_analytics.M3 as
select a.*, CONTRACT_NUMBER,       MANDATE_REQ_DATE,MANDATE_REQ_DATE1,maker_date ,txn_id, entry_type,mandate_status,transaction_date,Creation_Date,Author_Date
from risk_analytics.M1  a
left join  risk_analytics.M2  b on a.BATCH_NUMBER=b.BATCH_NUMBER and CONTRACT_NUMBER=CUSTOMER_REF_NO
left join (select Unique_ID,`Loan_Account_#`, MANDATE_REQ_DATE1,mandate_status,Transaction_Date,Creation_Date,maker_date,Author_Date  from axle ) c on Unique_ID=a.BATCH_NUMBER and `Loan_Account_#`=CONTRACT_NUMBER

-- COMMAND ----------

create or replace table risk_analytics.xzmandate as
select 
case when sys='Finnone' then Creation_Date else MANDATE_REQ_DATE end as start_Dt,
case when sys='Finnone' then MANDATE_REQ_DATE1 else LAST_MODIFIED_DATE end as end_Dt,Creation_Date,
CONTRACT_NUMBER,BATCH_NUMBER,status
from 
(
    select CONTRACT_NUMBER,BATCH_NUMBER,Creation_Date,MANDATE_REQ_DATE1,MANDATE_REQ_DATE,LAST_MODIFIED_DATE,STATUS,
    case when len(CONTRACT_NUMBER) in (7,8,9) then 'Autofin' 
         when len(CONTRACT_NUMBER)=12 then 'Finnone' 
         when len(CONTRACT_NUMBER) in (14) then 'Penannt' else null end as sys,
    row_number() over (partition by CONTRACT_NUMBER order by MANDATE_REQ_DATE desc) as rn
    from risk_analytics.M3
    where MANDATE_REQ_DATE between '2023-04-01' and '2026-03-31' or Creation_Date is not null
) a
where rn = 1

-- limit 2

-- COMMAND ----------

create or replace table risk_analytics.foremimandate as
select * from 
(SELECT 
case when upper(status) in ('ACTIVE',	'COMPLETED',	'BLOCKED',	'CLOSED') then 'ACCEPT' 
when upper(status) in (	'REJECT',	'REJECTED') then 'REJECT' 
end as STATUS,   start_Dt , CASE
            WHEN start_Dt BETWEEN  '2023-04-01' AND  '2024-03-31'   then 'FY24'
            WHEN start_Dt BETWEEN  '2024-04-01' AND  '2025-03-31' then  'FY25'
            WHEN start_Dt BETWEEN  '2025-04-01' AND  '2026-03-31' then 'FY26' 
            end as flag,                  CONTRACT_NUMBER,end_Dt
from risk_analytics.xzmandate
where  status in ('ACTIVE',	'COMPLETED',	'BLOCKED',	'CLOSED')
and start_Dt between  '2023-04-01' and '2026-03-31'  
)am where flag is not null

-- 1716728
-- group by 1,2/

-- COMMAND ----------

create or replace table risk_analytics.M4 as
select CONTRACT_NUMBER,INSTALMENT_DATE from mmfsl_prod.fusion_silverplus.cc_instalment_structure 
where CONTRACT_NUMBER in (select CONTRACT_NUMBER from risk_analytics.foremi
  ) and INSTALMENT_NO=1

-- COMMAND ----------

select * from risk_analytics.M4

-- COMMAND ----------

create or replace table risk_analytics.M5 as
select a.*,INSTALMENT_DATE
from risk_analytics.foremimandate a left join  risk_analytics.M4 b on a.CONTRACT_NUMBER=b.CONTRACT_NUMBER
-- where  start_Dt between '2023-04-01' and '2026-03-31' and   status in ('ACTIVE',	'COMPLETED',	'BLOCKED',	'CLOSED')

-- COMMAND ----------

select * from risk_analytics.M5

-- COMMAND ----------

select case when INSTALMENT_DATE <= end_Dt then 'Activated after EMI' 
when INSTALMENT_DATE > end_Dt then 'Activated before EMI' 
else 'BLINDER' end as flin, CASE
            WHEN start_Dt BETWEEN  '2023-04-01' AND  '2024-03-31'   then 'FY24'
            WHEN start_Dt BETWEEN  '2024-04-01' AND  '2025-03-31' then  'FY25'
            WHEN start_Dt BETWEEN  '2025-04-01' AND  '2026-03-31' then 'FY26'
            end as flagg,
            count(distinct CONTRACT_NUMBER)
 from risk_analytics.M5 
--  where  status in ('ACTIVE',	'COMPLETED',	'BLOCKED',	'CLOSED')

 group by 1,2

-- COMMAND ----------

  select count(*)
    from
    (select *    from mmfsl_prod.autofin_silver.dc_fnmvt_details
     union all
select *    from mmfsl_prod.autofin_silver.dc_fnmvt_history)a
    join risk_analytics.M4 b on a.REFERENCE_NUMBER = b.CONTRACT_NUMBER
   where a.document_date = b.INSTALMENT_DATE
     and a.sequence_type in ('X')
     AND a.REFERENCE_NUMBER IN (SELECT CONTRACT_NUMBER FROM mmfsl_prod.fusion_silverplus.ecs_batch_master UNION ALL SELECT CONTRACT_NUMBER FROM mmfsl_prod.autofin_silver.ecs_batch_master_hist)
     AND a.BRANCH_CODE = 'HO'
     AND UPPER(a.NARRATION) LIKE '%ACH RECEIPT%';

-- COMMAND ----------

SELECT
    date_format(b.INSTALMENT_DATE, 'yyyyMM') AS yyyymm,
    COUNT(DISTINCT b.CONTRACT_NUMBER) AS distinct_contract_count
FROM
(
    SELECT *
    FROM mmfsl_prod.autofin_silver.dc_fnmvt_details

    UNION ALL

    SELECT *
    FROM mmfsl_prod.autofin_silver.dc_fnmvt_history
) a
JOIN risk_analytics.M4 b
    ON a.REFERENCE_NUMBER = b.CONTRACT_NUMBER
WHERE a.document_date = b.INSTALMENT_DATE
    AND a.sequence_type = 'X'
    AND a.REFERENCE_NUMBER IN (
        SELECT CONTRACT_NUMBER
        FROM mmfsl_prod.fusion_silverplus.ecs_batch_master

        UNION ALL

        SELECT CONTRACT_NUMBER
        FROM mmfsl_prod.autofin_silver.ecs_batch_master_hist
    )
    AND a.BRANCH_CODE = 'HO'
    AND UPPER(a.NARRATION) LIKE '%ACH RECEIPT%'
GROUP BY date_format(b.INSTALMENT_DATE, 'yyyyMM')
ORDER BY yyyymm;

-- COMMAND ----------


select count (distinct CONTRACT_NUMBER) from risk_analytics.x5_1 bs
 
join (
select Receipt_Status,LOAN_ACCOUNT_NUMBER,Transaction_Date,Return_Reason_Description
from mmfsl_prod.finnone_silver.fct_receipt
where Receipt_Status='B'
) bnc
on bs.CONTRACT_NUMBER = bnc.LOAN_ACCOUNT_NUMBER and bs.INSTALMENT_DATE = bnc.Transaction_Date
 
where bs.src = 'Finnone' and bs.ACTIVATION = 'Activated before EMI'
-- and return_reason_description ='Mandate Not Received'
 

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW temp_mandate AS
select  CONTRACT_NUMBER from risk_analytics.x5_1 bs
 
join (
select Receipt_Status,LOAN_ACCOUNT_NUMBER,Transaction_Date,Return_Reason_Description
from mmfsl_prod.finnone_silver.fct_receipt
where Receipt_Status='B'
) bnc
on bs.CONTRACT_NUMBER = bnc.LOAN_ACCOUNT_NUMBER and bs.INSTALMENT_DATE = bnc.Transaction_Date
 
where bs.src = 'Finnone' and bs.ACTIVATION = 'Activated before EMI'
-- and return_reason_description ='Mandate Not Received'
 

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW vw_mandate AS

SELECT DISTINCT Count( a.NEW_HPANO),
    a.acct_yyyymm,

    CASE
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) >= 4
            THEN CONCAT(
                    'FY',
                    RIGHT(CAST(CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 1, 4) AS INT) + 1 AS STRING), 2)
                 )
        ELSE CONCAT(
                    'FY',
                    RIGHT(CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 1, 4) AS STRING), 2)
                 )
    END AS fiscal_year,

    CASE
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) BETWEEN 4 AND 6 THEN 'Q1'
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) BETWEEN 7 AND 9 THEN 'Q2'
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) BETWEEN 10 AND 12 THEN 'Q3'
        ELSE 'Q4'
    END AS fiscal_quarter,

    CASE
        WHEN b.CONTRACT_NUMBER IS NOT NULL THEN 'Y'
        ELSE 'N'
    END AS bounce_flag

FROM mmfsl_prod.fusion_silverplus.dctran a
LEFT JOIN temp_mandate b
    ON TRIM(a.NEW_HPANO) = TRIM(b.CONTRACT_NUMBER)
WHERE a.acct_yyyymm BETWEEN 202204 AND 202603
  AND a.STATUS <> 'E'
GROUP BY 2, 3, 4, 5;

-- COMMAND ----------

select * from vw_mandate

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW temp_npa_contracts AS
SELECT
    bs.CONTRACT_NUMBER
FROM risk_analytics.x5_1 bs
INNER JOIN (
    SELECT
        HPA_NO,
        REPORT_DATE,
        AGE_CNT_DPD
    FROM fusion_silverplus.npa_days_entry
) npa
    ON bs.CONTRACT_NUMBER = npa.HPA_NO
   AND CAST(bs.INSTALMENT_DATE AS DATE) = CAST(npa.REPORT_DATE AS DATE)
WHERE npa.AGE_CNT_DPD > 0;

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW vw_first_emi_bounce_flag AS

SELECT DISTINCT Count( a.NEW_HPANO),
    a.acct_yyyymm,

    CASE
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) >= 4
            THEN CONCAT(
                    'FY',
                    RIGHT(CAST(CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 1, 4) AS INT) + 1 AS STRING), 2)
                 )
        ELSE CONCAT(
                    'FY',
                    RIGHT(CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 1, 4) AS STRING), 2)
                 )
    END AS fiscal_year,

    CASE
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) BETWEEN 4 AND 6 THEN 'Q1'
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) BETWEEN 7 AND 9 THEN 'Q2'
        WHEN CAST(SUBSTR(CAST(a.acct_yyyymm AS STRING), 5, 2) AS INT) BETWEEN 10 AND 12 THEN 'Q3'
        ELSE 'Q4'
    END AS fiscal_quarter,

    CASE
        WHEN b.CONTRACT_NUMBER IS NOT NULL THEN 'Y'
        ELSE 'N'
    END AS bounce_flag

FROM mmfsl_prod.fusion_silverplus.dctran a
LEFT JOIN temp_npa_contracts b
    ON TRIM(a.NEW_HPANO) = TRIM(b.CONTRACT_NUMBER)
WHERE a.acct_yyyymm BETWEEN 202204 AND 202603
  AND a.STATUS <> 'E'
GROUP BY 2, 3, 4, 5;

-- COMMAND ----------

select * from vw_first_emi_bounce_flag

-- COMMAND ----------

 
select  quarter(INSTALMENT_DATE),year(INSTALMENT_DATE), count(CONTRACT_NUMBER)
from mmfsl_prod.fusion_silverplus.cc_instalment_structure ,mmfsl_prod.fusion_silverplus.npa_days_entry
where INSTALMENT_DATE between '2023-04-01' and '2026-03-31' and    INSTALMENT_NO=1 and INSTALMENT_DATE=REPORT_DATE and AGE_CNT_DPD > 0 and HPA_NO=CONTRACT_NUMBER
 
group by 1,2
 

-- COMMAND ----------

SELECT
    date_format(cast(INSTALMENT_DATE AS DATE), 'yyyyMM') AS yyyymm,

    CASE
        WHEN MONTH(INSTALMENT_DATE) >= 4
            THEN CONCAT('FY', RIGHT(CAST(YEAR(INSTALMENT_DATE) + 1 AS STRING), 2))
        ELSE CONCAT('FY', RIGHT(CAST(YEAR(INSTALMENT_DATE) AS STRING), 2))
    END AS fiscal_year,

    CASE
        WHEN MONTH(INSTALMENT_DATE) IN (4,5,6) THEN 'Q1'
        WHEN MONTH(INSTALMENT_DATE) IN (7,8,9) THEN 'Q2'
        WHEN MONTH(INSTALMENT_DATE) IN (10,11,12) THEN 'Q3'
        WHEN MONTH(INSTALMENT_DATE) IN (1,2,3) THEN 'Q4'
    END AS fiscal_quarter,

    COUNT(DISTINCT CONTRACT_NUMBER) AS cnt

FROM risk_analytics.x5

WHERE INSTALMENT_DATE <= end_Dt   -- Activated after EMI

GROUP BY 1,2,3
ORDER BY 1;