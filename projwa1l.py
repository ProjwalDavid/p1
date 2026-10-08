

import win32com.client
import pandas as pd
import re
import os
from datetime import datetime, timedelta, timezone

DAYS_TO_DOWNLOAD =365
 
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
OUTPUT_FILE = fr"C:\email_inventory_{timestamp}.xlsx"
 

TRACKING_FILE = r"C:\proces.csv"
 

processed_ids = set()
 
if os.path.exists(TRACKING_FILE):
    try:
        processed_df = pd.read_csv(TRACKING_FILE)
        processed_ids = set(processed_df["entry_id"].astype(str))
        print(f"Loaded {len(processed_ids)} processed IDs")
    except:
        pass
 
new_processed = []
 
 
def extract_recipients(recipients, recipient_type):
 
    emails = []
 
    try:
 
        for r in recipients:
 
            if r.Type != recipient_type:
                continue
 
            email = None
 
            try:
                exch_user = r.AddressEntry.GetExchangeUser()
 
                if exch_user:
                    email = exch_user.PrimarySmtpAddress
 
            except:
                pass
 
            if not email:
                try:
                    email = r.Address
                except:
                    pass
 
            if email:
                emails.append(email)
 
    except:
        pass
 
    return ",".join(sorted(set(emails)))
 
# =====================================================
# OUTLOOK CONNECTION
# =====================================================
 
outlook = win32com.client.Dispatch("Outlook.Application")
namespace = outlook.GetNamespace("MAPI")
 
inbox = namespace.GetDefaultFolder(6)
 
messages = inbox.Items
messages.Sort("[ReceivedTime]", True)
 
# =====================================================
# DATE FILTER
# =====================================================
 
cutoff_utc = datetime.now(timezone.utc) - timedelta(days=DAYS_TO_DOWNLOAD)
 
extract_timestamp = datetime.now(timezone.utc).isoformat()
 
records = []
 
# =====================================================
# PROCESS EMAILS
# =====================================================
 
for msg in messages:
 
    try:
 
        if msg.MessageClass != "IPM.Note":
            continue
 
        entry_id = str(msg.EntryID)
 
        # ------------------------------------------
        # SKIP PREVIOUSLY PROCESSED
        # ------------------------------------------
 
        if entry_id in processed_ids:
            continue
 
        # ------------------------------------------
        # TIME1
        # ------------------------------------------
 
        received_local = pd.Timestamp(msg.ReceivedTime)
 
        if received_local.tzinfo is None:
            received_local = received_local.tz_localize(
                datetime.now().astimezone().tzinfo
            )
 
        received_utc = received_local.tz_convert("UTC")
 
        if received_utc.to_pydatetime() < cutoff_utc:
            break
 
        # ------------------------------------------
        # SENDER
        # ------------------------------------------
 
        sender_name = None
        sender_email = None
 
        try:
            sender_name = msg.SenderName
        except:
            pass
 
        try:
            exch_user = msg.Sender.GetExchangeUser()
 
            if exch_user:
                sender_email = exch_user.PrimarySmtpAddress
 
        except:
            pass
 
        if not sender_email:
            try:
                sender_email = msg.SenderEmailAddress
            except:
                pass
 

 
        def get_smtp_address(recipient):
         
            try:
                exch_user = recipient.AddressEntry.GetExchangeUser()
         
                if exch_user:
                    return exch_user.PrimarySmtpAddress
            except:
                pass
         
            try:
                return recipient.PropertyAccessor.GetProperty(
                    "http://schemas.microsoft.com/mapi/proptag/0x39FE001E"
                )
            except:
                pass
         
            try:
                return recipient.Address
            except:
                pass
         
            return None
         
        to_emails = []
        cc_emails = []
         
        for r in msg.Recipients:
         
            email = get_smtp_address(r)
         
            if not email:
                continue
         
            if r.Type == 1:      # TO
                to_emails.append(email)
         
            elif r.Type == 2:    # CC
                cc_emails.append(email)
         
        to_emails = ",".join(sorted(set(to_emails)))
        cc_emails = ",".join(sorted(set(cc_emails)))
         
        recipient_count = msg.Recipients.Count
         
 
        # ------------------------------------------
        # SUBJECT
        # ------------------------------------------
 
        subject = str(msg.Subject or "")
 
        # ------------------------------------------
        # BODY
        # ------------------------------------------
 
        body_raw = ""
 
        try:
            body_raw = msg.Body
        except:
            pass
 
        body_clean = body_raw
 
        patterns = [
            r"(?is)-----Original Message-----.*",
            r"(?is)From:.*?Sent:.*"
        ]
 
        for p in patterns:
            body_clean = re.sub(
                p,
                "",
                body_clean
            )
 
        body_clean = body_clean.strip()
 
        # ------------------------------------------
        # CONVERSATION
        # ------------------------------------------
 
        try:
            conversation_id = msg.ConversationID
        except:
            conversation_id = None
 
        try:
            conversation_topic = msg.ConversationTopic
        except:
            conversation_topic = None
 
        # ------------------------------------------
        # RECORD
        # ------------------------------------------
 
        records.append({
 
            "extract_timestamp": extract_timestamp,
 
            "entry_id": entry_id,
 
            "conversation_id": conversation_id,
            "conversation_topic": conversation_topic,
 
            "sender_name": sender_name,
            "sender_email": sender_email,
 
            "to_emails": to_emails,
            "cc_emails": cc_emails,
            "recipient_count": recipient_count,
 
            "subject": subject,
 
            "received_local": received_local.isoformat(),
            "received_utc": received_utc.isoformat(),
 
            "attachment_count": msg.Attachments.Count,
 
            "body_clean": body_clean
 
        })
 
        new_processed.append({
            "entry_id": entry_id,
            "processed_timestamp": extract_timestamp
        })
 
    except Exception as e:
        print(e)
  
df = pd.DataFrame(records)
 
 
if len(df) > 0:
    df=df.astype(str)
    df.to_excel(OUTPUT_FILE,index=False )
 

 
if len(new_processed) > 0:
 
    tracking_df = pd.DataFrame(new_processed)
 
    if os.path.exists(TRACKING_FILE):
 
        tracking_df.to_csv(
            TRACKING_FILE,
            mode="a",
            header=False,
            index=False
        )
 
    else:
 
        tracking_df.to_csv(
            TRACKING_FILE,
            index=False
        )
 
# =====================================================
# SUMMARY
# =====================================================
 
print("=" * 60)
print(f"New Emails Processed : {len(df)}")
print(f"Tracking Records     : {len(new_processed)}")
print(f"Output File          : {OUTPUT_FILE}")
print(f"Tracking File        : {TRACKING_FILE}")
print("=" * 60)



from pathlib import Path
import pandas as pd
 
# Folder containing Excel files
folder = Path(r"D:\email\Emailbox")
 
outpt= folder.parent
# Get all Excel files
files = list(folder.glob("*.xlsx"))
 
# Group files by prefix (before first "_")
groups = {}
 
for file in files:
    prefix = file.name.split("_")[0]
    groups.setdefault(prefix, []).append(file)
 
# Merge each group
for prefix, file_list in groups.items():
 
    # Skip if there is only one file
    if len(file_list) < 2:
        continue
 
    print(f"\nMerging {prefix}:")
    
    dataframes = []
 
    for file in file_list:
        print(f"  {file.name}")
        df = pd.read_excel(file)
        dataframes.append(df)
 
    merged_df = pd.concat(dataframes, ignore_index=True)
 
    output_file = outpt / f"{prefix}_merged.xlsx"
    merged_df.to_excel(output_file, index=False)
 
    print(f"Created: {output_file}")
    
    