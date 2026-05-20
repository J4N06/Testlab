#!/bin/bash
set -e

VM_IDS=(200 201 202)

for ID in "${VM_IDS[@]}"; do
    if qm status "$ID" &>/dev/null; then
        echo ">>> Stoppe und lösche VM $ID..."
        qm stop "$ID" --skiplock 2>/dev/null || true
        qm destroy "$ID" --destroy-unreferenced-disks 1 --purge 1
    else
        echo ">>> VM $ID existiert nicht, überspringe."
    fi
done

echo "✓ Alle VMs gelöscht."
