# Matthew Hutchinson
# July 19 2024


#!/bin/bash


# Get the pcs status output
pcs_status=$(pcs status)

# Count the number of VIPs in the pcs status
vip_count=$(echo "$pcs_status" | grep -oP 'IPaddr2' | wc -l)

# Check if there is more than one VIP
if [ "$vip_count" -gt 1 ]; then
    echo "Error: More than one VIP found. Unsupported for this script. VIP count: $vip_count"
    exit 1
else
    echo "Only one VIP found. Proceeding."
fi


# Extract IP addresses from pcs status
nodes=$(pcs status | awk '
    /Node List:/ {flag=1; next}
    /Full List of Resources:/ {flag=0}
    flag && /Online:/ {
        gsub(/.*\[ /, "", $0)  # Remove everything before the IPs
        gsub(/ \]/, "", $0)    # Remove the closing bracket
        gsub(/ /, "\n", $0)   # Replace spaces with newlines to separate IPs
        print
    }
')

# Function to install packages on a node
install_packages() {
    local node_ip=$1
    ssh -T "$node_ip" << 'EOF'
        if command -v dnf &> /dev/null; then
            dnf install -y resource-agents
        elif command -v apt &> /dev/null; then
            apt update && apt install -y resource-agents
        else
            echo "Unsupported package manager. Please install resource-agents manually."
            exit 1
        fi
EOF
}

# Function to deploy the resource script on a node
deploy_resource_script() {
    local node_ip=$1
    ssh -T "$node_ip" << 'EOF'
        #!/bin/bash

        # Create the nfs-monitor resource script
        cat << 'SCRIPT' > /usr/lib/ocf/resource.d/heartbeat/nfs-monitor
#!/bin/bash

. /usr/lib/ocf/lib/heartbeat/ocf-shellfuncs

case "$1" in
    start)
        exit $OCF_SUCCESS
        ;;
    stop)
        exit $OCF_SUCCESS
        ;;
    monitor)
        if systemctl is-active --quiet nfs-server; then
            exit $OCF_SUCCESS
        else
            ocf_exit_reason "NFS server is not running"
            exit $OCF_NOT_RUNNING
        fi
        ;;
    meta-data)
        cat << 'METAEOF'
<?xml version="1.0"?>
<!DOCTYPE resource-agent SYSTEM "ra-api-1.dtd">
<resource-agent name="nfs-monitor">
    <version>1.0</version>
    <longdesc lang="en">
        This resource agent monitors the NFS server service.
    </longdesc>
    <shortdesc lang="en">NFS server monitor</shortdesc>
    <parameters/>
    <actions>
        <action name="start" timeout="5s" />
        <action name="stop" timeout="5s" />
        <action name="monitor" timeout="10s" interval="15s" />
        <action name="meta-data" timeout="5s" />
    </actions>
</resource-agent>
METAEOF
        exit $OCF_SUCCESS
        ;;
    *)
        echo "Usage: $0 {start|stop|monitor|meta-data}"
        exit $OCF_ERR_ARGS
        ;;
esac
SCRIPT

        # Make the script executable
        chmod +x /usr/lib/ocf/resource.d/heartbeat/nfs-monitor

        echo "Resource script deployment complete."
EOF
}

# Loop through each node IP
for node_ip in $nodes; do
    install_packages "$node_ip"
    deploy_resource_script "$node_ip"
done
pcs resource create nfs-monitor ocf:heartbeat:nfs-monitor op monitor interval=10s meta migration-threshold=1 failure-timeout=5s
pcs constraint colocation add nfs_ip with nfs-monitor INFINITY

echo "Resource deployment completed on all nodes."
