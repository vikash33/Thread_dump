#!/bin/bash -xe

# Define ENV, Host, Timestamp
ENV=$(hostname -f | awk -F "-" 'BEGIN {OFS="-"} {print $1 $2}')
BASENAME=$(hostname -s)
DATE_TAG=$(date "+%Y%m%d_%H%M%S")
DUMP_DIR="/tmp/thread_dumps_${BASENAME}_${DATE_TAG}"
DUMP_TAR="/tmp/${BASENAME}_dumps_${DATE_TAG}.tar"

mkdir -p "$DUMP_DIR"

echo ">>>>> Detecting Java Process >>>>>"
JAVA_PID=$(pgrep -f java)
if [ -z "$JAVA_PID" ]; then
  echo "❌ No running Java process found. Exiting cleanly."
  exit 0
fi
echo "✅ Java PID: $JAVA_PID"

echo ">>>>> Capturing Thread Dumps >>>>>"
for i in {1..3}; do
  jstack -l "$JAVA_PID" > "$DUMP_DIR/${BASENAME}_thread_${i}.txt"
  sleep 5
done

echo ">>>>> Capturing CPU Snapshot >>>>>"
top -b -n 1 > "$DUMP_DIR/${BASENAME}_top.txt"

echo ">>>>> Archiving dump files >>>>>"
tar -cvf "$DUMP_TAR" -C "$DUMP_DIR" .
rm -rf "$DUMP_DIR"

echo ">>>>> Authenticating with GCP >>>>>"
CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
if [[ "$CURRENT_ACCOUNT" != *"compute@"* ]]; then
  echo "🔐 Activating service account"
  gcloud auth activate-service-account --key-file=~/key.json
else
  echo "✅ Authenticated as: $CURRENT_ACCOUNT"
fi

echo ">>>>> Uploading to GCS: gs://cust01-heapdump_demo/ >>>>>"
gsutil cp "$DUMP_TAR" gs://cust01-heapdump_demo/
gsutil ls -la gs://cust01-heapdump_demo/$(basename "$DUMP_TAR")

echo "✅ Thread dump archived and uploaded."

# Optional cleanup
rm -f "$DUMP_TAR"
