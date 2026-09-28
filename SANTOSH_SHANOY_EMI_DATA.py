# Databricks notebook source
# MAGIC %md
# MAGIC AUTOFIN DATA

# COMMAND ----------

# DBTITLE 1,DUE DATA
# MAGIC %sql
# MAGIC create or replace table risk_analytics.SANTOSH_INST_DT as
# MAGIC SELECT CONTRACT_NUMBER, INST_NO, INSTALMENT_AMOUNT,instalment_date,INST_yyyymm
# MAGIC FROM (
# MAGIC   SELECT CONTRACT_NUMBER, 
# MAGIC          INSTALMENT_NO AS INST_NO, 
# MAGIC          INSTALMENT_AMOUNT, 
# MAGIC         INSTALMENT_DATE, 
# MAGIC          date_format(INSTALMENT_DATE,'yyyyMM') as INST_yyyymm,
# MAGIC          ROW_NUMBER() OVER (PARTITION BY CONTRACT_NUMBER ORDER BY INSTALMENT_NO DESC) AS rn
# MAGIC   FROM fusion_silverplus.cc_instalment_structure 
# MAGIC ) t where instalment_date between '2025-04-01' and '2026-08-31'
# MAGIC

# COMMAND ----------

# DBTITLE 1,MAIN BASE TABLE
# MAGIC %sql
# MAGIC create or replace table risk_analytics.SANTOSH_BR_DT as
# MAGIC select REFERENCE_NUMBER,INSTRUMENT_NUMBER,RECEIPT_DATE,case when INSTRUMENT_TYPE='1.000000000000000000' then 'LOCAL CHEQUE' else 'CHEQUE' end as RCPT_PAYMENT_MODE ,date_format(RECEIPT_DATE,'yyyyMM') as rcpt_yyyymm,IFSC_CODE
# MAGIC from mmfsl_prod.autofin_silver.dc_online_receipt_header a, mmfsl_prod.autofin_silver.dc_online_receipt_details b
# MAGIC where a.ONLINE_NUMBER=b.ONLINE_NUMBER  and RECEIPT_DATE between '2025-04-01' and '2026-08-31'  and INSTRUMENT_TYPE='1.000000000000000000'

# COMMAND ----------

# DBTITLE 1,RECEIPT BASE
# MAGIC %skip
# MAGIC %sql
# MAGIC create or replace table risk_analytics.SANTOSH_RCPT_DT as
# MAGIC SELECT REF_TYPE_NUM, RCPT_AMT, DOCUMENT_DATE, TXN_ACCOUNT, PAYMENT_MODE,RCPT_yyyymm
# MAGIC FROM (
# MAGIC   SELECT REF_TYPE_NUM, TXN_AMT as RCPT_AMT, DOCUMENT_DATE, TXN_ACCOUNT, PAYMENT_MODE,date_format(DOCUMENT_DATE,'yyyyMM') as RCPT_yyyymm,
# MAGIC          ROW_NUMBER() OVER (PARTITION BY REF_TYPE_NUM ORDER BY DOCUMENT_DATE DESC) AS rn
# MAGIC   FROM fusion_silverplus.tbl_rcpt_dtl
# MAGIC   WHERE TXN_ACCOUNT='SBDRS1' and  DOCUMENT_DATE between '2025-04-01' and '2026-08-31' 
# MAGIC ) t
# MAGIC

# COMMAND ----------

# DBTITLE 1,CHEQUE DETAILS
# MAGIC %skip
# MAGIC %sql
# MAGIC create or replace table risk_analytics.santosh_pdc as
# MAGIC select CONTRACT_NUMBER,CHEQUE_NUMBER,CHEQUE_DATE,TXN_AMT  as CHEQUE_PD_AMT,date_format(CHEQUE_DATE,'yyyyMM') as CHEQUE_yyyymm
# MAGIC from fusion_silverplus.pd_batch_master a
# MAGIC left join fusion_silverplus.pd_cheque_details b on a.BATCH_NUMBER=b.BATCH_NUMBER
# MAGIC where CHEQUE_DATE between '2025-04-01' and '2026-08-31'  

# COMMAND ----------

# DBTITLE 1,MAIN QUERY
# MAGIC %sql
# MAGIC create or replace table  risk_analytics.SANTOSH_FNL_DATA as
# MAGIC select distinct a.REFERENCE_NUMBER as NEW_HPANO,a.CHEQUE_NUMBER,a.RECEIPT_DATE,a.PDC_AMT,c.INSTALMENT_AMOUNT as DUE_AMT,c.instalment_date as DUE_DATE,d.TXN_ACCOUNT,a.RCPT_PAYMENT_MODE,a.rcpt_yyyymm,a.IFSC_CODE
# MAGIC from risk_analytics.SANTOSH_BR_DT a
# MAGIC left join risk_analytics.SANTOSH_INST_DT c on a.REFERENCE_NUMBER=c.CONTRACT_NUMBER and a.RCPT_yyyymm=c.INST_yyyymm
# MAGIC left join risk_analytics.SANTOSH_RCPT_DT d on a.REFERENCE_NUMBER=d.REF_TYPE_NUM
# MAGIC --left join risk_analytics.santosh_pdc d on a.ref_type_num=d.CONTRACT_NUMBER and a.RCPT_yyyymm=d.CHEQUE_yyyymm
# MAGIC where a.PDC_AMT<c.INSTALMENT_AMOUNT and d.TXN_ACCOUNT='SBDRS1'
# MAGIC --and payment_mode in ('LOCAL CHEQUE','CHEQUE')
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC select a.*,
# MAGIC b.name as Customer_name,
# MAGIC mmfsl_prod.admin.fn_decrypt(c.PAN) as Customer_PAN,
# MAGIC b.BRANCH as Contract_Branch,
# MAGIC b.STATUS as Contract_status,
# MAGIC b.AGE as OD_Age,
# MAGIC b.OUTSTAND as OD_amount
# MAGIC from risk_analytics.SANTOSH_FNL_DATA a
# MAGIC left join fusion_silverplus.dctran b on a.NEW_HPANO=b.NEW_HPANO
# MAGIC join fusion_silverplus.tbl_dc_extn c on a.NEW_HPANO=c.NEW_HPANO

# COMMAND ----------

# MAGIC %skip
# MAGIC %sql
# MAGIC MERGE INTO risk_analytics.SANTOSH_FNL_DATA a
# MAGIC USING (
# MAGIC   SELECT REFERENCE_NUMBER, CHEQUE_NUMBER, RCPT_YYYYMM
# MAGIC   FROM (
# MAGIC     SELECT *, ROW_NUMBER() OVER (PARTITION BY REFERENCE_NUMBER, RCPT_YYYYMM ORDER BY CHEQUE_NUMBER) AS rn
# MAGIC     FROM risk_analytics.SANTOSH_BR_DT
# MAGIC   )
# MAGIC   WHERE rn = 1
# MAGIC ) b
# MAGIC ON a.new_hpano = b.reference_number AND a.rcpt_yyyymm = b.RCPT_yyyymm
# MAGIC   AND a.cheque_number IS NULL
# MAGIC WHEN MATCHED THEN UPDATE SET cheque_number = b.cheque_number

# COMMAND ----------

# MAGIC %sql
# MAGIC select * from ofas_silver.fct_transaction_details where REF_NO='9660547' and DOC_DT between '2025-04-01' and '2026-08-31'

# COMMAND ----------

# MAGIC %md
# MAGIC FINNONE DATA

# COMMAND ----------

# MAGIC %sql
# MAGIC select * from fusion_silverplus.cc_instalment_structure

# COMMAND ----------

# MAGIC %sql
# MAGIC select count(NEW_HPANO) from fusion_silverplus.dctran 
# MAGIC where (ACC_IRR < 8 or ACC_IRR > 40) and HPA_DATE between '2024-04-01' and '2026-03-31'

# COMMAND ----------

# MAGIC %sql
# MAGIC create or replace table risk_analytics.SANTOSH_FINN_RECEIPT as
# MAGIC select
# MAGIC round(RECEIPT_PAYMENT_REF_NUMBER,2) as Receipt_Ref_No,
# MAGIC LOAN_ACCOUNT_NUMBER,GP.DESCRIPTION as Payment_Mode,
# MAGIC date(Transaction_Date) as Date_of_Receipt,
# MAGIC Case when RD.receipt_payout_channel = 'BRANCH' THEN 'OTC' else 'NON-OTC' end as Repayment_Indicator,
# MAGIC R.Instrument_Reference_Number,
# MAGIC R.RECEIPT_NUMBER,date_format(transaction_date,'yyyyMM') as RCPT_yyyymm,
# MAGIC round(R.Transaction_Amount,2) as Receipt_Amount,
# MAGIC case
# MAGIC when R.Receipt_Status = 'D' THEN 'Deposit Author'
# MAGIC when R.Receipt_Status = 'C' THEN 'Realized'
# MAGIC when R.Receipt_Status = 'B' THEN 'Bounced'
# MAGIC when R.Receipt_Status = 'X' THEN 'Cancelled'
# MAGIC when R.Receipt_Status = 'R' THEN 'Entered'
# MAGIC else R.Receipt_Status end as Receipt_Status
# MAGIC from finnone_silver.fct_receipt R
# MAGIC left join finnone_silver.dim_generic_parameter GP on R.Payment_Mode = GP.GENERIC_PARAMETER_ID
# MAGIC left join lms_silver.fct_receipt_details RD on R.RECEIPT_NUMBER = RD.receipt_id
# MAGIC where GP.DESCRIPTION = 'Cheque'
# MAGIC and Transaction_Date between '2025-04-01' and '2026-08-31'
# MAGIC order by R.LOAN_ACCOUNT_NUMBER,R.Transaction_Date desc

# COMMAND ----------

# MAGIC %sql
# MAGIC select a.LOAN_ACCOUNT_NUMBER,a.Repayment_Indicator,a.Instrument_Reference_Number,a.Date_of_Receipt as PDC_DATE,a.Receipt_Amount as PDC_AMOUNT,d.instalment_date as DUE_DATE,d.INSTALMENT_AMOUNT as DUE_AMT,d.INST_NO,b.name as Customer_name,
# MAGIC mmfsl_prod.admin.fn_decrypt(c.PAN) as Customer_PAN,
# MAGIC b.BRANCH as Contract_Branch,
# MAGIC b.STATUS as Contract_status,
# MAGIC b.AGE as OD_Age,
# MAGIC b.OUTSTAND as OD_amount from risk_analytics.SANTOSH_FINN_RECEIPT a
# MAGIC left join risk_analytics.santosh_inst_dt d on a.LOAN_ACCOUNT_NUMBER=d.CONTRACT_NUMBER 
# MAGIC left join fusion_silverplus.dctran b on a.LOAN_ACCOUNT_NUMBER=b.NEW_HPANO
# MAGIC left join fusion_silverplus.tbl_dc_extn c on a.LOAN_ACCOUNT_NUMBER=c.NEW_HPANO
# MAGIC where LOAN_ACCOUNT_NUMBER='001001310994'

# COMMAND ----------

# MAGIC %sql
# MAGIC select a.LOAN_ACCOUNT_NUMBER,a.Repayment_Indicator,a.Instrument_Reference_Number,a.Date_of_Receipt as PDC_DATE,a.Receipt_Amount as PDC_AMOUNT,d.instalment_date as DUE_DATE,d.INSTALMENT_AMOUNT as DUE_AMT,d.INST_NO,b.name as Customer_name,
# MAGIC mmfsl_prod.admin.fn_decrypt(c.PAN) as Customer_PAN,
# MAGIC b.BRANCH as Contract_Branch,
# MAGIC b.STATUS as Contract_status,
# MAGIC b.AGE as OD_Age,
# MAGIC b.OUTSTAND as OD_amount 
# MAGIC from risk_analytics.SANTOSH_FINN_RECEIPT a
# MAGIC left join risk_analytics.santosh_inst_dt d on a.LOAN_ACCOUNT_NUMBER=d.CONTRACT_NUMBER 
# MAGIC left join fusion_silverplus.dctran b on a.LOAN_ACCOUNT_NUMBER=b.NEW_HPANO
# MAGIC left join fusion_silverplus.tbl_dc_extn c on a.LOAN_ACCOUNT_NUMBER=c.NEW_HPANO
# MAGIC where  Receipt_Amount<INSTALMENT_AMOUNT

# COMMAND ----------

# MAGIC %sql
# MAGIC select distinct count(*) from fusion_silverplus.dctran where ACC_IRR  and HPA_DATE between '2024-04-01' and '2026-03-31'







--Autofin
-- 1. EMI due per contract per month
create or replace table risk_analytics.SANTOSH_INST_DT as
select CONTRACT_NUMBER,
       date_format(INSTALMENT_DATE,'yyyyMM')                          as INST_YYYYMM,
       min(INSTALMENT_DATE)                                           as DUE_DATE,
       concat_ws(',', array_sort(collect_list(cast(INSTALMENT_NO as string)))) as INST_NOS,
       sum(INSTALMENT_AMOUNT)                                         as DUE_AMT
from fusion_silverplus.cc_instalment_structure
where INSTALMENT_DATE between '2025-04-01' and '2026-08-31'
group by CONTRACT_NUMBER, date_format(INSTALMENT_DATE,'yyyyMM');

-- 2. Cheque (PDC) receipts per contract per month
create or replace table risk_analytics.SANTOSH_BR_DT as
select REFERENCE_NUMBER                                    as CONTRACT_NUMBER,
       date_format(RECEIPT_DATE,'yyyyMM')                  as RCPT_YYYYMM,
       count(*)                                            as NO_OF_CHEQUES,
       concat_ws(',', collect_list(INSTRUMENT_NUMBER))     as CHEQUE_NUMBERS,
       min(RECEIPT_DATE)                                   as FIRST_RECEIPT_DATE,
       max(IFSC_CODE)                                      as IFSC_CODE,
       sum(<RECEIPT_AMOUNT_COLUMN>)                        as PDC_AMT   -- replace with the actual amount column
from mmfsl_prod.autofin_silver.dc_online_receipt_header a
join mmfsl_prod.autofin_silver.dc_online_receipt_details b
  on a.ONLINE_NUMBER = b.ONLINE_NUMBER
where RECEIPT_DATE between '2025-04-01' and '2026-08-31'
  and INSTRUMENT_TYPE = '1.000000000000000000'
  -- optional: keep only cheques registered as PDCs
  -- and exists (select 1
  --             from fusion_silverplus.pd_batch_master m
  --             join fusion_silverplus.pd_cheque_details d on m.BATCH_NUMBER = d.BATCH_NUMBER
  --             where d.CONTRACT_NUMBER = REFERENCE_NUMBER
  --               and cast(d.CHEQUE_NUMBER as bigint) = cast(INSTRUMENT_NUMBER as bigint))
group by REFERENCE_NUMBER, date_format(RECEIPT_DATE,'yyyyMM');

-- 3. Short PDC cases
create or replace table risk_analytics.SANTOSH_FNL_DATA as
select p.CONTRACT_NUMBER as NEW_HPANO, p.RCPT_YYYYMM, p.NO_OF_CHEQUES, p.CHEQUE_NUMBERS,
       p.FIRST_RECEIPT_DATE, p.IFSC_CODE, p.PDC_AMT,
       i.DUE_DATE, i.INST_NOS, i.DUE_AMT,
       i.DUE_AMT - p.PDC_AMT as SHORTFALL
from risk_analytics.SANTOSH_BR_DT p
join risk_analytics.SANTOSH_INST_DT i
  on p.CONTRACT_NUMBER = i.CONTRACT_NUMBER
 and p.RCPT_YYYYMM     = i.INST_YYYYMM
where p.PDC_AMT < i.DUE_AMT;

-- 4. Enrich with customer details
select a.*,
       b.NAME as Customer_name,
       mmfsl_prod.admin.fn_decrypt(c.PAN) as Customer_PAN,
       b.BRANCH as Contract_Branch, b.STATUS as Contract_status,
       b.AGE as OD_Age, b.OUTSTAND as OD_amount
from risk_analytics.SANTOSH_FNL_DATA a
left join fusion_silverplus.dctran     b on a.NEW_HPANO = b.NEW_HPANO
left join fusion_silverplus.tbl_dc_extn c on a.NEW_HPANO = c.NEW_HPANO;



---- Finnone 
select r.LOAN_ACCOUNT_NUMBER, r.RCPT_yyyymm,
       count(*)                                                as NO_OF_CHEQUES,
       concat_ws(',', collect_list(r.Instrument_Reference_Number)) as CHEQUE_NUMBERS,
       sum(r.Receipt_Amount)                                   as PDC_AMT,
       i.DUE_DATE, i.INST_NOS, i.DUE_AMT,
       i.DUE_AMT - sum(r.Receipt_Amount)                       as SHORTFALL
from risk_analytics.SANTOSH_FINN_RECEIPT r
join risk_analytics.SANTOSH_INST_DT i
  on r.LOAN_ACCOUNT_NUMBER = i.CONTRACT_NUMBER
 and r.RCPT_yyyymm         = i.INST_YYYYMM
where r.Receipt_Status = 'Realized'
group by r.LOAN_ACCOUNT_NUMBER, r.RCPT_yyyymm, i.DUE_DATE, i.INST_NOS, i.DUE_AMT
having sum(r.Receipt_Amount) < i.DUE_AMT;
