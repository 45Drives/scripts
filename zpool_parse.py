import subprocess
import json

def parse_zpool_status():
    result = subprocess.run(['zpool', 'status'], stdout=subprocess.PIPE)
    output = result.stdout.decode('utf-8').splitlines()
    
    pools = {}
    current_pool = None
    current_section = None
    current_vdev = None
    current_helper_vdev = None

    for line in output:
        line = line.strip()
        if line.startswith('pool:'):
            current_pool = line.split()[1]
            pools[current_pool] = {'data_vdevs': [], 'helper_vdevs': [], 'state': '', 'scan': ''}
            current_section = 'data_vdevs'
            current_vdev = None
            current_helper_vdev = None
        elif line.startswith('state:'):
            pools[current_pool]['state'] = line.split()[1]
        elif line.startswith('scan:'):
            pools[current_pool]['scan'] = ' '.join(line.split()[1:])
        elif line.startswith('config:'):
            continue
        elif line.startswith('errors:'):
            current_section = None
        elif line.startswith('NAME') or line.startswith('----') or line == '':
            continue
        elif 'raidz' in line or (current_section == 'data_vdevs' and 'mirror' in line):
            current_vdev = {'type': line, 'disks': []}
            pools[current_pool]['data_vdevs'].append(current_vdev)
        elif 'special' in line or 'log' in line or 'cache' in line:
            current_helper_vdev = {'type': line, 'vdevs': []}
            pools[current_pool]['helper_vdevs'].append(current_helper_vdev)
            current_section = 'helper_vdevs'
        elif current_section == 'helper_vdevs' and 'mirror' in line:
            current_vdev = {'type': line, 'disks': []}
            current_helper_vdev['vdevs'].append(current_vdev)
        else:
            parts = line.split()
            if len(parts) < 2:
                # Logging for debugging
                print(f"Skipping line (unexpected format): {line}")
                continue

            name = parts[0]
            if current_section == 'data_vdevs' and current_vdev:
                current_vdev['disks'].append(name)
            elif current_section == 'helper_vdevs' and current_helper_vdev:
                if current_vdev and 'mirror' in current_vdev['type']:
                    current_vdev['disks'].append(name)
                else:
                    current_helper_vdev['vdevs'].append({'type': 'disk', 'disks': [name]})

    return json.dumps(pools, indent=4)

if __name__ == '__main__':
    print(parse_zpool_status())

