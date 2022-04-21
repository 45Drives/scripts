#!/bin/bash
# 45Drives- Brett Kelly
# Stable 1.0

# To get an idea of how long this will take
# Run time rados -p $INDEX_POOL listomapkeys $obj
# ETC = (Time to List index objects) + (Time to list data pool) + (# Number of Bucket Shards) * (# of failed MPU) * (time it takes to list an omap key) 

usage() { # Help
cat << EOF
    Usage:	
        [-b] S3 Bucket name. Required
        [-e] RGW S3 Endpoint. Required. IP or FQDN is supported. i.e http://192.168.123.121:8080
        [-c] This flag will tell the script to remove the underlying MPU objects. 
             By default script will run in "dry-run" mode and not delete any underlying objects, only printing to stdout what would be done.
        [-h] Displays this message
EOF
    exit 1
}
check_dependancies(){
    for i in "${!SCRIPT_DEPENDANCIES[@]}"; do
        if ! command -v ${SCRIPT_DEPENDANCIES[i]} >/dev/null 2>&1;then
	        echo "cli tool: ${SCRIPT_DEPENDANCIES[i]} is not installed"
            echo "${SCRIPT_DEPENDANCIES[@]} are required"
	        exit 1
        fi
    done
}
check_endpoint(){
    if [ -z $ENDPOINT ];then
        echo "Error: Ceph RGW S3 endpoint required"
        usage
    else
        echo "checking to see if endpoint is listening..."
        if ! curl $ENDPOINT >/dev/null 2>&1 ; then
            echo "Error: endpoint $ENDPOINT is unreachable"
            exit 1
        fi
    fi
}
check_s3_access(){
    if [ -z $BUCKET_NAME ];then
        echo "Error: Bucket name required"
        usage
    else
        echo "checking to see if s3 creds work and if bucket exists..."
        if aws --endpoint-url=$ENDPOINT s3api head-bucket --bucket $BUCKET_NAME 2>/dev/null ; then 
            echo "Bucket $BUCKET_NAME exists"
        else
            echo "Error: Either bucket $BUCKET_NAME does not exist or s3 credentials are incorrect/dont have permission to access bucket"
            exit 1
        fi
    fi
}

ECHO_IF_DRYRUN="echo"
SCRIPT_DEPENDANCIES=(aws jq radosgw-admin)
DATE=$(date +"%Y-%m-%d")
UUID=$(uuidgen | cut -d - -f 1)

while getopts 'b:e:d:i:ch' OPTION; do
    case ${OPTION} in
    b)
        BUCKET_NAME="${OPTARG}"
        ;;
    e)
        ENDPOINT="${OPTARG}"
        ;;
    c)
        ECHO_IF_DRYRUN=
        ;;
    h)
        usage
        ;;
    esac
done

if [ $# -eq 0 ];then
    echo "User input is required"
    usage
    exit 1
fi

check_dependancies
check_endpoint
check_s3_access

if [ "$ECHO_IF_DRYRUN" == "echo" ];then
    echo "*******************************"
    echo "RUNNING IN DRY RUN MODE..."
    echo "To commit process use '-c' flag"
    echo "*******************************"
fi

echo "Getting bucket stats for $BUCKET_NAME..."
BUCKET_STATS_JSON=$(radosgw-admin bucket stats --bucket $BUCKET_NAME)
if [ -z "$BUCKET_STATS_JSON" ];then
    echo "Error getting bucket stats, bucket does not exist"
    exit 1
fi

echo "Getting list of failed multipart uploads..."
MPU_JSON=$(aws --endpoint-url=$ENDPOINT s3api list-multipart-uploads --bucket $BUCKET_NAME)
if [ -z "$MPU_JSON" ];then
    echo "There are no failed multipart uploads present in bucket : $BUCKET_NAME"
    exit 1
fi

# Determine which rados pools are used by the bucket 
BUCKET_PLACEMENT=$(echo $BUCKET_STATS_JSON | jq -r '.placement_rule') # default-placement
BUCKET_ZONE_ID=$(echo $BUCKET_STATS_JSON | jq -r '.marker' | cut -d . -f 1) # 05681bdc-46bb-4cc2-8098-3db875a692cd
PLACEMENT_POOLS_JSON=$(radosgw-admin zone get --zone-id=$BUCKET_ZONE_ID | jq -r --arg placement "$BUCKET_PLACEMENT" '.placement_pools | .[] | select(.key==$placement)')
RGW_DATA_POOL=$(echo $PLACEMENT_POOLS_JSON | jq -r '.val.storage_classes.STANDARD.data_pool')
RGW_INDEX_POOL=$(echo $PLACEMENT_POOLS_JSON | jq -r '.val.index_pool')
RGW_EXTRA_POOL=$(echo $PLACEMENT_POOLS_JSON | jq -r '.val.data_extra_pool')

# Verify each data,index and extra bucket exists on the cluster  
# VERIFY THAT DATA_POOL IS EC quit if its replicated
CEPH_POOLS=( $(ceph osd pool ls) )
for pool in $RGW_DATA_POOL $RGW_INDEX_POOL $RGW_EXTRA_POOL ; do
    if [[ ! " ${CEPH_POOLS[*]} " =~ " $pool " ]];then
        echo "error: $pool is not present in list of ceph pools. Error determining placement data pools"
        echo "RGW_DATA_POOL : $RGW_DATA_POOL"
        echo "RGW_INDEX_POOL : $RGW_INDEX_POOL"
        echo "RGW_EXTRA_POOL : $RGW_EXTRA_POOL"
        exit 1
    fi
done

BUCKET_ID=$(echo $BUCKET_STATS_JSON | jq -r '.id')
BUCKET_MARKER=$(echo $BUCKET_STATS_JSON | jq -r '.marker')
BUCKET_SHARD_COUNT=$(echo $BUCKET_STATS_JSON | jq -r '.num_shards')
MPU_COUNT=$(echo $MPU_JSON | jq '.Uploads | length')

# Get list of index objects
echo "Listing index pool objects. This may take some time..."
RGW_INDEX_POOL_OBJECTS=( $(rados -p $RGW_INDEX_POOL ls | grep $BUCKET_ID) )

echo "Listing extra pool objects. This may take some time..."
RGW_EXTRA_POOL_OBJECTS=( $(rados -p $RGW_EXTRA_POOL ls) )

## Loop through each failed MPU 
echo "Starting to remove failed MPU rados objects..."
i=0
while [ $i -lt $MPU_COUNT ]; do
    UPLOAD_ID=$(echo $MPU_JSON | jq -r .Uploads[$i].UploadId)
    UPLOAD_KEY=$(echo $MPU_JSON | jq -r .Uploads[$i].Key)

    MPU_META_OBJ=""$BUCKET_MARKER"__multipart_"$UPLOAD_KEY"."$UPLOAD_ID".meta"

    echo "Removing omap keys and data objects for upload: $UPLOAD_KEY.$UPLOAD_ID : [$(( i + 1 )) / $MPU_COUNT]"
    if `rados -p $RGW_EXTRA_POOL get $MPU_META_OBJ - &>/dev/null`;then
        echo ".meta object is present in extra pool. Use s3 client to abort"
        if [ "$ECHO_IF_DRYRUN" == "echo" ];then
            echo "aws --endpoint-url=$ENDPOINT s3api abort-multipart-upload --bucket $BUCKET_NAME --key $UPLOAD_KEY --upload-id $UPLOAD_ID"
        else
            echo "aws --endpoint-url=$ENDPOINT s3api abort-multipart-upload --bucket $BUCKET_NAME --key $UPLOAD_KEY --upload-id $UPLOAD_ID" >> mpu-$DATE-$UUID.log
        fi
    else
        for index_obj in "${RGW_INDEX_POOL_OBJECTS[@]}" ; do
            OMAP_KEYS=( $(rados -p $RGW_INDEX_POOL listomapkeys $index_obj | grep "$UPLOAD_KEY.$UPLOAD_ID") )
            for key in ${OMAP_KEYS[@]}; do
                $ECHO_IF_DRYRUN rados -p $RGW_INDEX_POOL rmomapkey $index_obj $key
                if echo $key | grep -vq ".meta";then 
                    $ECHO_IF_DRYRUN rados -p $RGW_DATA_POOL rm "$BUCKET_MARKER"_"$key"
                fi 
            done
        done
    fi
    let i=i+1
done

if [ "$ECHO_IF_DRYRUN" == "echo" ];then
    echo "*******************************"
    echo "Dry Run complete"
    echo "To commit process use '-c' flag"
    echo "*******************************"
else
    echo "*******************************"    
    echo "Finished removing failed MPU objects"
    echo "Space is now freed in the cluster, but a bucket reshard is required to update bucket metadata"
    echo "radosgw-admin bucket reshard --bucket=$BUCKET_NAME --num-shards=<Next Prime Number>"
    echo "*******************************"
fi