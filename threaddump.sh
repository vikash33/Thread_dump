#!/bin/bash -xe

ENV=$(hostname -f | awk -F "-" 'BEGIN {OFS="-"} {print $1 $2}')

echo ">>>>> Cleaning up old thread dump files >>>>>"
rm -rf /tmp/$(hostname -s)*.txt
rm -rf /tmp/$(hostname -s)*.top
rm -rf /tmp/$(hostname -s)_dumps*.tar

echo ">>>>> Converting file format & setting permissions >>>>>"
dos2unix /tmp/threaddump.sh
chmod 777 /tmp/threaddump.sh

echo ">>>>> Running thread dump >>>>>"
sh /tmp/threaddump.sh $(pidof java)

sleep 10

echo ">>>>> Checking CPU & Memory >>>>>"
CPU_USAGE=$(top -b -n2 -p 1 | grep "Cpu(s)" | tail -1 | awk -F'id,' '{ split($1, vs, ","); v=vs[length(vs)]; sub("%", "", v); printf "%.1f%%", 100 - v }')
MEMORY_USAGE=$((sar -r | awk '{print $4}') | tail -1)

myfilesize=$(wc -c /tmp/$(hostname -s)*.txt | awk '{print $1}' | head -1)

if [ "$myfilesize" != "0" ]; then
  DUMP_FILE="/tmp/$(hostname -s)_dumps_$RANDOM.tar"
  tar -cvf "$DUMP_FILE" /tmp/$(hostname -s)*.txt /tmp/$(hostname -s)*.top

  echo ">>>>> Authenticating with GCP (if needed) >>>>>"
  CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
  if [[ "$CURRENT_ACCOUNT" != *"compute@"* ]]; then
    echo "🔐 Using service account key"
    gcloud auth activate-service-account --key-file=~/key.json
  else
    echo "✅ Authenticated as $CURRENT_ACCOUNT"
  fi

  echo ">>>>> Uploading to GCS >>>>>"
  gsutil cp "$DUMP_FILE" gs://cust01-heapdump_demo/WFMThreadDumps/$ENV/
  ls -ltr "$DUMP_FILE"
  gsutil ls -la gs://cust01-heapdump_demo/WFMThreadDumps/$ENV/$(basename "$DUMP_FILE")

  echo -e 'Hello Team,\n\nThread dump completed on '"$(hostname)"'.\nDump location:\n'"$(gsutil ls -la gs://cust01-heapdump_demo/WFMThreadDumps/$ENV/$(basename "$DUMP_FILE"))"'\n\nThanks,\nUKG Cloud Support' | \
  s-nail -S smtp=cust01-oss01-mta01-app.int.oss.mykronos.com:25 -r noreply@mykronos.com -s "✅ Thread Dump Completed on $(hostname)" kgswfdcloudsupportall@ukg.com

else
  echo -e 'Hello Team,\n\nThread dump aborted on '"$(hostname)"' due to high CPU/Memory.\nCPU: '"$CPU_USAGE"', Memory: '"$MEMORY_USAGE"'\nPlease retry manually.\n\nThanks,\nUKG Cloud Support' | \
  s-nail -S smtp=cust01-oss01-mta01-app.int.oss.mykronos.com:25 -r noreply@mykronos.com -s "⚠️ Thread Dump Aborted on $(hostname)" kgswfdcloudsupportall@ukg.com
fi

if [[ "$CURRENT_ACCOUNT" != *"compute@"* ]]; then
  gcloud auth revoke svc-cust-sup-user@gcp-cust01.iam.gserviceaccount.com
fi
