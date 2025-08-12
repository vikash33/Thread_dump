#!/bin/bash -xe

ENV=$(hostname -f | awk -F "-" 'BEGIN {OFS="-"} {print $1 $2}')

echo ">>>>> Cleaning up old thread dump files >>>>>"
sudo rm -rf /tmp/$(hostname -s)*.txt
sudo rm -rf /tmp/$(hostname -s)*.top
sudo rm -rf /tmp/$(hostname -s)_dumps*.tar

echo ">>>>> Converting file format & setting permissions >>>>>"
sudo dos2unix /tmp/threaddump.sh
sudo chmod 777 /tmp/threaddump.sh

echo ">>>>> Running thread dump >>>>>"
sudo sh /tmp/threaddump.sh $(pidof java)

sleep 10

echo ">>>>> Checking CPU & Memory >>>>>"
CPU_USAGE=$(top -b -n2 -p 1 | grep "Cpu(s)" | tail -1 | awk -F'id,' '{ split($1, vs, ","); v=vs[length(vs)]; sub("%", "", v); printf "%.1f%%", 100 - v }')
MEMORY_USAGE=$((sar -r | awk '{print $4}') | tail -1)

myfilesize=$(wc -c /tmp/$(hostname -s)*.txt | awk '{print $1}' | head -1)

if [ "$myfilesize" != "0" ]; then
  DUMP_FILE="/tmp/$(hostname -s)_dumps_$RANDOM.tar"
  sudo tar -cvf "$DUMP_FILE" /tmp/$(hostname -s)*.txt /tmp/$(hostname -s)*.top

  echo ">>>>> Authenticating with GCP (if needed) >>>>>"
  CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
  if [[ "$CURRENT_ACCOUNT" != *"compute@"* ]]; then
    echo "🔐 Using service account key"
    sudo gcloud auth activate-service-account --key-file=/usr/local/key.json
  else
    echo "✅ Authenticated as $CURRENT_ACCOUNT"
  fi

  echo ">>>>> Uploading to GCS >>>>>"
  sudo gsutil cp "$DUMP_FILE" gs://cust01-heapdump_demo/WFMThreadDumps/$ENV/
  sudo ls -ltr "$DUMP_FILE"
  sudo gsutil ls -la gs://cust01-heapdump_demo/WFMThreadDumps/$ENV/$(basename "$DUMP_FILE")

  sudo -u root -i sh -c "echo -e 'Hello Team,\n\nThread dump completed on $(hostname).\nDump location:\n$(gsutil ls -la gs://cust01-heapdump_demo/WFMThreadDumps/$ENV/$(basename "$DUMP_FILE"))\n\nThanks,\nUKG Cloud Support'" |

