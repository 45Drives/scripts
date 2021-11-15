#!/bin/bash
# 45Drives
# Brett Kelly

## FUNCTIONS
usage() { # Help
cat << EOF
    Usage:
        [-l] Update nfsv3 for selected export. Comma separated list of EXPORT_ID. <1,2,3>. Not required if "-a" flag is used
        [-a] Update nfsv3 for all exports
        [-e] Enable nfsv3 for selected export(s)
        [-d] Disable nfsv3 for selected export(s) 
        [-h] Displays this message
EOF
    exit 0
}
printerr(){
    echo $1
    exit 1
}
getExports(){
    EXPORTS=( $(rados -p nfs_ganesha -N ganesha-export ls | grep export | sort) )
}
getExportConf(){
    EXPORT_CONFIGS=( $(rados -p nfs_ganesha -N ganesha-export ls | grep conf | sort) )
}
printRow(){
    printf "%-12s | %-12s | %-12s\n" "$1" "$2" "$3"
}
enableNFSV3(){
    rados -p nfs_ganesha -N ganesha-export get $1 - |\
    sed "s/protocols = 4;/protocols = 3,4;/g" |\
    rados -p nfs_ganesha -N ganesha-export put $1 -
}
disableNFSV3(){
    rados -p nfs_ganesha -N ganesha-export get $1 - |\
    sed "s/protocols = 3,4;/protocols = 4;/g" |\
    rados -p nfs_ganesha -N ganesha-export put $1 -
}
updateExport(){
    if [ "$ENABLE_V3" == "true" ];then
        enableNFSV3 $1
    elif [ "$DISABLE_V3" == "true" ];then
        disableNFSV3 $1
    fi 
}
notifyGanesha(){
    rados -p nfs_ganesha -N ganesha-export notify $1 "" &> /dev/null
}

displayExports(){
    getExports
    printRow "EXPORT_ID" "EXPORT_PATH" "PROTOCOL_VERSION"
    printRow "---------" "-----------" "----------------"
    for export in ${EXPORTS[@]};do
        export_object=$(rados -p nfs_ganesha -N ganesha-export get $export -)
        export_id=$( echo "$export_object" | grep export_id | awk '{print $3}' | cut -d ";" -f1)
        path=$( echo "$export_object" | grep path | awk '{print $3}' | cut -d '"' -f 2)
        protocols=$( echo "$export_object" | grep protocols  | awk '{print $3}' | cut -d ";" -f1)
        printRow "$export_id" "$path" "$protocols"
    done
}

#INIT
ENABLE_ALL="false"
ENABLE_V3="false"
DISABLE_V3="false"

# GET USER INPUT
while getopts 'adel:sh' OPTION; do
    case ${OPTION} in
    a)
        ENABLE_ALL="true"
        ;;
    d)
        DISABLE_V3="true"
        ;;
    e)
        ENABLE_V3="true"
        ;;
    l)
        input=${OPTARG}
        IFS=',' read -r -a _EXPORT_LIST <<< "$input"
        EXPORT_LIST=$(printf '%s\n'  "${_EXPORT_LIST[@]}" | awk '!a[$0]++')
        ;;
    s)
        displayExports
        exit 0
        ;;
    h)
        usage
        ;;
    esac
done

#VERIFY USER INPUT
if [ "$ENABLE_V3" == "false" ] && [ "$DISABLE_V3" == "false" ];then
    printerr "Error: enable (-e) or (-d) flag is required"
fi
if [ "$ENABLE_V3" == "true" ] && [ "$DISABLE_V3" == "true" ];then
    printerr "Error: Both enable and disable flags provided"
fi
if [ "$ENABLE_ALL" != "true" ] && [ -z "$EXPORT_LIST" ];then
    printerr "Error: list of exports required"
fi

#MAIN
getExports
if [ "$ENABLE_ALL" == "true" ];then
    for export in ${EXPORTS[@]};do
        updateExport $export
    done
else
    for export_id in ${EXPORT_LIST[@]};do
        for export in ${EXPORTS[@]};do
            id=$( rados -p nfs_ganesha -N ganesha-export get $export - | grep export_id | awk '{print $3}' | cut -d ";" -f1)
            if [ "$export_id" == "$id" ];then
                updateExport $export
            fi
        done
    done
fi

getExportConf
for conf in ${EXPORT_CONFIGS[@]};do
    notifyGanesha $conf
done