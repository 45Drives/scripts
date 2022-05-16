#!/usr/bin/bash
usage() { 
	echo "Options: e - Enable Offline Repos, d - Disable Offline Repos" >&2
}

while getopts "ed" o; do
    case "${o}" in
        e)
            ENABLE_OFFLINE=true
            ;;
        d)
            DISABLE_OFFLINE=true
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

if [[ -n $ENABLE_OFFLINE && -n $DISABLE_OFFLINE ]]; then
	echo "cannot use both e and d options simultaneously"
	exit 1
fi

OFFLINE_REPO_FILES=$(ls -al /etc/yum.repos.d | grep .*-local.repo | awk '{print $NF}')
OFFLINE_REPOS=''
for repofile in $OFFLINE_REPO_FILES; do
	OFFLINE_REPOS+=$(grep -oP '\[.*?\]' /etc/yum.repos.d/$repofile | sed 's/[][]//g')" "
done

#echo $OFFLINE_REPOS

ONLINE_REPOS=''
for repo in $OFFLINE_REPOS; do
	ONLINE_REPOS+=$(echo $repo | sed 's/-local//g')" "
done

#echo $ONLINE_REPOS

if [[ -n $ENABLE_OFFLINE ]]; then
	echo "Disabling Online Repos:"
	echo $ONLINE_REPOS
	for repo in $ONLINE_REPOS; do
		dnf config-manager --set-disabled $repo
	done
	dnf config-manager --set-disabled ceph_stable
	dnf config-manager --set-disabled ceph_stable_noarch
	echo "Enabling Offline Repos:"
	echo $OFFLINE_REPOS
	for repo in $OFFLINE_REPOS; do
		dnf config-manager --set-enabled $repo
	done
elif [[ -n $DISABLE_OFFLINE ]]; then
	echo "Disabling Offline Repos:"
	echo $OFFLINE_REPOS
	for repo in $OFFLINE_REPOS; do
		dnf config-manager --set-disabled $repo
	done
	echo "Enabling Online Repos:"
	echo $ONLINE_REPOS
	for repo in $ONLINE_REPOS; do
		dnf config-manager --set-enabled $repo
	done
	dnf config-manager --set-enabled ceph_stable
	dnf config-manager --set-enabled ceph_stable_noarch
else
	usage
	exit 1
fi
