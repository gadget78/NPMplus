#!/bin/bash
# installer for NPMplus 
# sched_setaffinity alerts, in /etc/pve/lxc/xxx.conf set `lxc.cgroup2.cpuset.cpus: 0-4` and reboot

source <(curl -s https://raw.githubusercontent.com/community-scripts/core/main/core/core.func)
load_functions

####################################
## check if install has been set
if [[ -z "${install_npmplus:-}" ]]; then
    if command -v docker &> /dev/null; then
        # Check if the container 'npmplus' is present
        if docker ps -a --format '{{.Names}}' | grep -q '^npmplus$'; then
            echo -e "${DGN}Container 'npmplus' is present. carrying out update${CL}"
            install_npmplus="false"
        else
            echo -e "${DGN}Container 'npmplus' is NOT present. carrying out install${CL}"
            install_npmplus="true"
        fi
    else
        echo -e "${DGN}Docker is NOT installed. carrying out install${CL}"
        install_npmplus="true"
    fi
fi

[[ -n "$FUNCTIONS_FILE_PATH" ]] && source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
load_functions
####################################
## start install if needed
if [[ "$install_npmplus" == "true" ]]; then
    if [[ "${install_type:-}" == "CT" ]]; then
        color
        verb_ip6
        catch_errors
        setting_up_container
        network_check
        update_os
    else
        STD=""
    fi

    msg_info "Installing Dependencies"
    $STD apt-get install -y curl
    $STD apt-get install -y sudo
    $STD apt-get install -y mc
    msg_ok "Installed Dependencies"

    ####################################
    ## check if version has been set
    if [[ "${install_version:-}" == "latest" ]]; then
        msg_ok "latest version requested."
        prerun_folder="/opt/npmplus/prerun/"
        admin_email="admin@example.org"
    elif curl -sf "https://hub.docker.com/v2/repositories/zoeyvid/npmplus/tags/$install_version/" > /dev/null; then
        msg_ok "version $install_version present on dockerhub."
        prerun_folder="/opt/npmplus/prerun/"
        admin_email="admin@example.org"
    else
        msg_ok "version corrected to latest."
        install_version="latest"
        prerun_folder="/opt/npmplus/prerun/"
        admin_email="admin@example.org"
    fi

    DOCKER_LATEST_VERSION=$(curl -sL https://api.github.com/repos/moby/moby/releases/latest | grep '"tag_name":' | cut -d'"' -f4 )
    PORTAINER_LATEST_VERSION=$(curl -sL https://api.github.com/repos/portainer/portainer/releases/latest | grep '"tag_name":' | cut -d'"' -f4 )
    PORTAINER_AGENT_LATEST_VERSION=$(curl -sL https://api.github.com/repos/portainer/agent/releases/latest | grep '"tag_name":' | cut -d'"' -f4 )
    DOCKER_COMPOSE_LATEST_VERSION=$(curl -sL https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4 )

    msg_info "Installing Docker $DOCKER_LATEST_VERSION"
    DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
    mkdir -p $(dirname $DOCKER_CONFIG_PATH)
    echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
    $STD sh <(curl -sSL https://get.docker.com)
    msg_ok "Installed Docker $DOCKER_LATEST_VERSION"

    msg_info "Installing Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p $DOCKER_CONFIG/cli-plugins
    curl -sSL https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_LATEST_VERSION/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose
    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
    msg_ok "Installed Docker Compose $DOCKER_COMPOSE_LATEST_VERSION"

    if [[ "$install_portainer" == "true" ]]; then
    msg_info "Installing Portainer $PORTAINER_LATEST_VERSION"
    docker volume create portainer_data >/dev/null
    $STD docker run -d \
    -p 8000:8000 \
    -p 9443:9443 \
    --name=portainer \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest
    msg_ok "Installed Portainer $PORTAINER_LATEST_VERSION"
    else
    msg_ok "Installing Portainer skipped"
    fi

    if [[ "${install_type:-}" == "CT" ]]; then
        motd_ssh
        customize
    fi

    msg_info "Cleaning up container"
    $STD apt-get -y autoremove
    $STD apt-get -y autoclean
    msg_ok "Container Cleaned"
    sleep 2

    echo -e "installing NPMplus via docker compose..."

####################################
## start update 
else
    msg_info "updating os..."
    apt-get update 2>&1 | awk '{ printf "\r\033[K   updating os... "; printf "%s", $0; fflush() }'
    msg_ok "updated os."

    ####################################
    ## check if version has been set
    if [[ "${install_version:-}" == "latest" ]]; then
        msg_ok "latest version requested."
        prerun_folder="/opt/npmplus/prerun/"
        admin_email="admin@example.org"
    elif curl -sf "https://hub.docker.com/v2/repositories/zoeyvid/npmplus/tags/$install_version/" > /dev/null; then
        msg_ok "version $install_version present on dockerhub."
        prerun_folder="/opt/npmplus/prerun/"
        admin_email="admin@example.org"
    else
        msg_ok "version corrected to latest."
        install_version="latest"
        prerun_folder="/opt/npmplus/prerun/"
        admin_email="admin@example.org"
    fi

    msg_info "creating backups.."
    backup_error=""
    {
        if [[ -d "/opt/npmplus" ]]; then
            cp -r /opt/npmplus /opt/npmplus-BACKUP-$(date +%Y-%m-%d_%H-%M-%S) || backup_error+="error: backing up folder /opt/npmplus; "
        fi
        if [[ -d "/opt/npm" ]]; then
            if ! command -v rsync &> /dev/null; then
                apt-get install -y rsync 2>&1 | awk '{ printf "\r\033[K   installing rsync.. "; printf "%s", $0; fflush() }'
            fi
            cp -r /opt/npm /opt/npm-BACKUP-$(date +%Y-%m-%d_%H-%M-%S) || backup_error+="error: backing up folder /opt/npm; "
            rsync -a --remove-source-files /opt/npm/ /opt/npmplus/ && rm -rf /opt/npm/ || backup_error+="error: moving folder /opt/npm to /opt/npmplus; "
        fi
    } 
    if [[ -z "$backup_error" ]]; then
        msg_ok "All backups created successfully, and files moved for updated NPM+                               "
    else
        msg_error "Error(s) occurred when trying to create backups: $backup_error                                "
    fi

    echo -e "checking and pulling any updates for NPMplus image via docker compose...                 "
    docker compose -f ~/docker-compose-for-NPMplus.yml pull
fi
npm_restart="false"

####################################
## re-instate prerun script
mkdir -p $prerun_folder
cat << 'EOF' > "${prerun_folder}gadget_deploy.sh"
#!/bin/bash
echo ""
echo "gadgets 1st run custom deploy script now running...."
if grep -qw "worker_connections" /usr/local/nginx/conf/nginx.conf; then
    if [[ -d "/data/nginx_custom" ]]; then 
        rm /data/nginx_custom/events.conf || true
    elif [[ -d "/data/nginx/custom" ]]; then
        rm /data/nginx/custom/events.conf || true 
    elif [[ -d "/data/custom_nginx" ]]; then 
        rm /data/custom_nginx/events.conf || true
    else
        rm /data/custom_nginx/events.conf || true
    fi
    sed -i 's/^[[:space:]]*#*[[:space:]]*worker_connections.*/  worker_connections 65535;/' /usr/local/nginx/conf/nginx.conf && echo " - increased worker_connections to 65535 in main nginx.conf file" || { echo " ** failed to update worker_connections on file /usr/local/nginx/conf/nginx.conf"; true; }
else
    if [[ -d "/data/nginx_custom" ]]; then 
        sh -c 'echo "worker_connections 65535;" > /data/nginx_custom/events.conf' && echo " - increased worker_connections to 65535 (in file /data/nginx_custom/events.conf)" || { echo " ** failed to update worker_connections on file /data/nginx_custom/events.conf"; true; }
    elif [[ -d "/data/nginx/custom" ]]; then
        sh -c 'echo "worker_connections 65535;" > /data/nginx/custom/events.conf' && echo " - increased worker_connections to 65535 (in file /data/nginx/custom/events.conf)" || { echo " ** failed to update worker_connections on file /data/nginx/custom/events.conf"; true; }
    elif [[ -d "/data/custom_nginx" ]]; then 
        sh -c 'echo "worker_connections 65535;" > /data/custom_nginx/events.conf' && echo " - increased worker_connections to 65535 (in file /data/custom_nginx/events.conf)" || { echo " ** failed to update worker_connections on file /data/custom_nginx/events.conf"; true; }
    else
        sh -c 'mkdir -p /data/custom_nginx > /dev/null' && sh -c 'echo "worker_connections  65535;" > /data/custom_nginx/events.conf' && echo " - created events.conf, to increase worker_connections to 65535" || { echo " ** failed to create file /data/nginx_custom/events.conf"; true; }
    fi
fi

ulimit -n 192000 && echo " - increased open file resource" || { echo " ** failed to update open file resource value"; true; }
## sed -i "s/{{ forwarding_port }}/\\\$server_port/g" /app/templates/stream.conf && echo " - stream port template updated to support ranges" || { echo " ** failed to update stream range fix"; true; }
sed -i '/{% if value == "444" %}/,/{% else %}/ {s|ssl_reject_handshake on;|ssl_certificate /data/tls/dummycert.pem;\n    ssl_certificate_key /data/tls/dummykey.pem;|}' /app/templates/default.conf
sed -i -e '/upstream stream_upstream_{{ id }} {/,/^[[:space:]]*}[[:space:]]*$/d' -e 's|:\$server_port||g' /app/templates/stream.conf && echo " - applied fix for \$stream_port bug in template" || { echo " ** failed to apply \$stream_port fix"; true; }
sed -i 's|^\([[:space:]]*\)proxy_pass .*;|\1proxy_pass {{ forwarding_host }}:$server_port;|' /app/templates/stream.conf && echo " - stream port template updated to support ranges" || { echo " ** failed to update stream range fix"; true; }
sed -i 's/^\s*proxy_headers_hash_max_size\s\+[0-9]\+;/proxy_headers_hash_max_size 5120;/' /usr/local/nginx/conf/nginx.conf && echo " - proxy_headers_hash_max_size increased to 5120" || { echo " ** failed to increase proxy_headers_hash_max_size"; true; }
sed -i 's/^\s*proxy_headers_hash_bucket_size\s\+[0-9]\+;/proxy_headers_hash_bucket_size 5120;/' /usr/local/nginx/conf/nginx.conf && echo " - proxy_headers_hash_bucket_size increased to 5120" || { echo " ** failed to increase proxy_headers_hash_bucket_size"; true; }
sed -i 's/^\s*server_names_hash_bucket_size\s\+[0-9]\+;/server_names_hash_bucket_size 5120;/' /usr/local/nginx/conf/nginx.conf && echo " - server_names_hash_bucket_size increased to 5120" || { echo " ** failed to increase server_names_hash_bucket_size"; true; }
{ grep -q 'server_names_hash_max_size' /usr/local/nginx/conf/nginx.conf || sed -i '/server_names_hash_bucket_size/a\    server_names_hash_max_size 5120;' /usr/local/nginx/conf/nginx.conf; } && echo " - server_names_hash_max_size entry added" || { echo " ** failed to add entry server_names_hash_max_size"; true; }
sed -i '/access_log off; # stream/a\    error_log /usr/local/nginx/logs/stream_crit.log crit;  # Only log critical errors' /usr/local/nginx/conf/nginx.conf && echo " - error_log for streams increased to critical logging (to prevent refused entries being logged)" || { echo " ** failed to change stream logging to critical only"; true; }
sed -i '/"additionalProperties":/s/false/true/' /app/schema/paths/tokens/post.json && echo " - adjusted the API to except longer expiry times when creating token" || { echo " ** failed to update API for additional properties to allow use of expiry in token creation"; true; }
mv /data/prerun/gadget_deploy.sh /data/gadget_deploy.sh && echo " - successfully moved this pre-run deploy script, so it does not run again, moved to /data/gadget_deploy.sh" || { echo " ** unable to move the pre-run script /data/prerun/gadget_deploy.sh , this will cause it run every time on reboot."; true; }


# Create another pre-run script. so restarts do not escalate, and to check dscp tagging and routing is in place.
cat << 'ENDLINE' > /data/prerun/restart-checks.sh
#!/bin/sh

NGINX_PID_FILE="/usr/local/nginx/logs/nginx.pid"
LOG_FILE="/var/log/npm-pre-run.log"
mkdir -p "$(dirname "$LOG_FILE")"

# Redirect all output to both stdout and log file
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[$(date)] Starting NPM pre-run sequence"

# Graceful shutdown if PID file exists
if [ -f "$NGINX_PID_FILE" ] || pgrep nginx >/dev/null; then
    echo "[$(date)] PID exists, Attempting graceful Nginx shutdown"
    nginx -s quit
    sleep 20
    [ -f "$NGINX_PID_FILE" ] && rm -f "$NGINX_PID_FILE"
    
    # Verify graceful shutdown succeeded
    if [ -f "$NGINX_PID_FILE" ] || pgrep nginx >/dev/null; then
        echo "[$(date)] Graceful shutdown failed, PID still exists"
        echo "[$(date)] Attempting forceful Nginx termination"
        [ -f "$NGINX_PID_FILE" ] && rm -f "$NGINX_PID_FILE"
        pkill -9 nginx || echo "[$(date)] No Nginx processes found"
        sleep 40

    else
        echo "[$(date)] Graceful shutdown succeeded"
    fi
fi

# Final verification
if [ -f "$NGINX_PID_FILE" ] || pgrep nginx >/dev/null; then
    echo "[$(date)] ERROR: Failed to kill Nginx processes"
    exit 1
else
    echo "[$(date)] Successfully terminated all Nginx processes"
fi

echo "[$(date)] Pre-run cleanup completed successfully"
sleep 5
ENDLINE
chmod +x /data/prerun/restart-checks.sh && echo " - created a new prerun script, to make sure nginx is exited, so does not conflict if its being restarted" || { echo " ** failed to create new prerun script"; true; }

echo "gadget prerun deploy script finished, check logs above !"
EOF

####################################
## pull needed updates from repo, # and modify the compose file for our needs (adjust to work at scale, add timezone etc)
if [[ "${timezone:-}" != */* ]]; then
    timezone=$(
        cat /etc/timezone 2>/dev/null \
        || timedatectl show --property=Timezone --value 2>/dev/null \
        || readlink /etc/localtime | sed 's|.*/zoneinfo/||' 2>/dev/null \
        || echo "UTC"
    )
fi
escaped_timezone=$(printf '%s\n' "$timezone" | sed 's/[\/&]/\\&/g')

compose_file="$HOME/docker-compose-for-NPMplus.yml"
if [ -f "$compose_file" ]; then
    cookie_secret=$(sed -n 's/^[[:space:]]*-[[:space:]]*"COOKIE_SECRET=\([^"]*\)".*/\1/p' "$compose_file" | head -n1)
fi
if [ -z "${cookie_secret:-}" ]; then
    cookie_secret=$(openssl rand -hex 12)
else
    msg_ok "found existing COOKIE_SECRET from $compose_file, re-using to retain session/api tokens"
fi

curl -sSL https://github.com/ZoeyVid/NPMplus/raw/develop/compose.yaml -o $compose_file \
    && sed -i "s|zoeyvid/npmplus:latest|zoeyvid/npmplus:$install_version|g" $compose_file \
    && sed -i '/^    network_mode: host$/a\    ulimits:\n      nofile: 192000' $compose_file \
    && sed -i '/^      - NET_BIND_SERVICE$/a\      - NET_ADMIN\n      - NET_RAW' $compose_file \
    && sed -i '/^#  crowdsec:/,/^$/ s/^#//' $compose_file \
    && sed -i "s/^      - \"TZ=your-timezone\"/      - \"TZ=$escaped_timezone\"/g" $compose_file \
    && sed -i "s/^#      - \"ACME_EMAIL=.*\"/      - \"ACME_EMAIL=your@email.com\"/" $compose_file \
    && sed -i "s/^#      - \"ACME_PROFILE=shortlived\"/      - \"ACME_PROFILE=classic\"/" $compose_file \
    && sed -i "s/^#      - \"IPRT=.*\"/      - \"IPRT=48\"/" $compose_file \
    && sed -i "s/^#      - \"GOA=.*\"/      - \"GOA=true\"/" $compose_file \
    && sed -i "s/^#      - \"INITIAL_DEFAULT_PAGE=444\"/      - \"INITIAL_DEFAULT_PAGE=444\"/" $compose_file \
    && sed -i "s/^#      - \"NGINX_DISABLE_PROXY_BUFFERING=.*\"/      - \"NGINX_DISABLE_PROXY_BUFFERING=true\"/" $compose_file \
    && sed -i "s/^#      - \"NGINX_WORKER_CONNECTIONS=.*\"/      - \"NGINX_WORKER_CONNECTIONS=65535\"/" $compose_file \
    && sed -i "s/^#      - \"COOKIE_SECRET=.*\"/      - \"COOKIE_SECRET=$cookie_secret\"/" $compose_file \
    && sed -i "s/^#      - \"ENABLE_PRERUN=.*\"/      - \"ENABLE_PRERUN=true\"/" $compose_file \
    && sed -i "s/^#      - \"TOKEN_MAX_EXPIRY=720\"/      - \"TOKEN_MAX_EXPIRY=438000\"/" $compose_file \
    && { docker rm -f npmplus crowdsec anubis geoipupdate 2>/dev/null; } \
    && docker compose -f $compose_file up -d --force-recreate \
    && msg_ok "docker compose created, edited, and ran ok." \
    || { msg_error "something went wrong getting, adjusting, or running the compose file"; exit 1; }
echo

if [[ -f "/opt/crowdsec/conf/acquis.d/npmplus.yaml" ]]; then
    msg_ok "npmplus.yml file already present within crowdsec image, skipping creation."
else
    msg_info "creating npmplus.yml config file for crowdsec image..."
    mkdir -p /opt/crowdsec/conf/acquis.d/
    cat << 'EOF' > /opt/crowdsec/conf/acquis.d/npmplus.yaml
filenames:
  - /opt/npmplus/nginx/logs/*.log
labels:
  type: npmplus
---
listen_addr: 0.0.0.0:7422
appsec_config: crowdsecurity/appsec-default
name: appsec
source: appsec
labels:
  type: appsec
EOF
    msg_ok "created npmplus.yml config file for crowdsec image."
    npm_restart="true"
fi

timeout=0
while true; do
    if [[ -f "/opt/npmplus/crowdsec/crowdsec.conf" ]]; then
        break
    fi
    if (( timeout >= 300 )); then
        msg_error "timed out waiting for crowdsec.conf to be present"
        exit 1
    fi
    sleep 2
    (( timeout += 2 ))
done

if [[ "$(sed -n 's/^ENABLED=//p' "/opt/npmplus/crowdsec/crowdsec.conf" 2>/dev/null)" == "true"* ]]; then
    msg_ok "crowdsec is already enabled within npmplus."
else
    msg_info "enabling crowdsec within npmplus..."
    sed -i 's/^ENABLED=.*/ENABLED=true/' "/opt/npmplus/crowdsec/crowdsec.conf" \
      && msg_ok "crowdsec enabled within npmplus" && npm_restart="true" \
      || { msg_error "something went wrong enabling crowdsec within npmplus"; exit 1; }
fi

if [[ -z $(sed -n 's/^API_KEY=//p' "/opt/npmplus/crowdsec/crowdsec.conf" 2>/dev/null) ]]; then  
    msg_info "adding crowdsec api key to npmplus crowdsec.conf file..."
    add_output=$(docker exec crowdsec cscli bouncers add npmplus 2>&1)
    add_status=$?

    if [ $add_status -ne 0 ] && echo "$add_output" | grep -qi "already exists"; then
        msg_error "bouncer npmplus already exists, deleting and recreating"
        docker exec crowdsec cscli bouncers delete npmplus > /dev/null
        add_output=$(docker exec crowdsec cscli bouncers add npmplus 2>&1 || true )
        add_status=$?
    fi

    if [ $add_status -ne 0 ]; then
        msg_error "unable to create crowdsec bouncer for npmplus: $add_output"; exit 1;
    else
        CROWDSEC_API_KEY=$(echo "$add_output" | grep -E '^[[:space:]]*[A-Za-z0-9+/=]{20,}[[:space:]]*$' | tr -d '[:space:]')

        if [ -z "$CROWDSEC_API_KEY" ]; then
            msg_error "could not parse api key from cscli output: $add_output"
        else
            sed -i "s|^API_KEY=.*|API_KEY=$CROWDSEC_API_KEY|" "/opt/npmplus/crowdsec/crowdsec.conf" \
                && msg_ok "crowdsec api key added to npmplus crowdsec.conf file" \
                && npm_restart="true" \
                || { msg_error "something went wrong adding crowdsec api key to npmplus crowdsec.conf file"; exit 1; }
        fi
    fi
else
    msg_ok "crowdsec api key already present within npmplus crowdsec.conf file."
fi
echo


echo "Setting up stream IP fixes, via DSCP tagging and return-path routing..."

route_out=$(ip -4 route get 1.1.1.1 2>/dev/null)
iface=$(echo "$route_out" | awk '{for(n=1;n<=NF;n++) if($n=="dev"){print $(n+1); exit}}')
# --- src_valid_mark must be 0 on BOTH "all" and the interface (the kernel ORs them)
if [ -n "$iface" ]; then
    for key in all "$iface"; do
        k="net.ipv4.conf.$key.src_valid_mark"
        if [ "$(sysctl -n "$k" 2>/dev/null)" != "0" ]; then
            if sysctl -w "$k=0" >/dev/null 2>&1; then
                echo "set $k=0"
            fi
        fi
    done
fi

cat << 'ENDLINE' > $HOME/npmplus_dscp_check.sh
#!/bin/sh

dscp_val="0x07"
fwmark="7"
fwmark_hex=$(printf '%x' "$fwmark")
rt_table="107"
check_fail="0"

# --- wait for the network (at boot the route may not exist yet)
tries=0
while [ "$tries" -lt 60 ]; do
    local_ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(n=1;n<=NF;n++) if($n=="src"){print $(n+1); exit}}')
    [ -n "$local_ip" ] && break
    tries=$((tries+1)); sleep 2
done

if [ -n "$local_ip" ]; then

    # --- 1. nft: tag spoofed outbound packets + mark tagged return traffic (applied atomically)
    if nft list table ip dscp_tag 2>/dev/null | grep -q "saddr != $local_ip" \
    && nft list table ip dscp_steer >/dev/null 2>&1; then
        echo "  ✔️  nft rules already in place for $local_ip, skipping"
    else
        nft_rules="
            add table ip dscp_tag
            delete table ip dscp_tag
            table ip dscp_tag {
                chain output {
                    type filter hook output priority mangle; policy accept;
                    ip saddr != $local_ip ip dscp set $dscp_val
                }
            }
            add table ip dscp_steer
            delete table ip dscp_steer
            table ip dscp_steer {
                chain prerouting {
                    type filter hook prerouting priority mangle; policy accept;
                    ip dscp $dscp_val meta mark set $fwmark
                }
            }
        "
        printf '%s\n' "$nft_rules" | nft -f - || { echo "  ❌  ERROR: failed to apply nft rules"; check_fail="1"; }
    fi

    # --- 2. route first (the table must exist), then the rule that points at it
    ip route replace local 0.0.0.0/0 dev lo table "$rt_table" || { echo "  ❌  ERROR: route add failed"; check_fail="1"; }
    if ! ip rule show | grep -q "fwmark 0x$fwmark_hex lookup $rt_table"; then
        ip rule add fwmark "$fwmark" lookup "$rt_table" || { echo "  ❌  ERROR: ip rule add failed"; check_fail="1"; }
    fi

    if [ "$check_fail" = "0" ]; then echo "  ✔️  NPMplus stream IP tagging fully applied"; fi

else
    echo "  ❌  ERROR: could not detect local IP, stream IP tagging NOT (re)applied"
fi
ENDLINE
chmod +x $HOME/npmplus_dscp_check.sh
$HOME/npmplus_dscp_check.sh || msg_error "Stream IP fix reported errors"

printf '%s\n' \
    "[Unit]" \
    "Description=NPMplus stream IP fix (DSCP tag + local return route)" \
    "After=network-online.target" \
    "Wants=network-online.target" \
    "" \
    "[Service]" \
    "Type=oneshot" \
    "RemainAfterExit=yes" \
    "ExecStart=$HOME/npmplus_dscp_check.sh" \
    "" \
    "[Install]" \
    "WantedBy=multi-user.target" > /etc/systemd/system/npmplus-dscp.service
systemctl daemon-reload && systemctl enable npmplus-dscp.service >/dev/null 2>&1 && msg_ok "peristance service for dscp via systemd setup" || msg_error "Failed to setup persistant service for dscp"
echo

####################################
## finish off, and restart if needed
if [[ "$install_npmplus" == "true" ]]; then
    msg_ok "NPMplus has now been installed, and is running..."
    echo
    echo -e "${DGN}its available to login and setup at ${BGN}https://$(hostname -I | awk '{print $1}'):81${CL}"
    # echo
    # echo -e "${DGN}- default login on old versions;${CL}"
    # echo -e "${DGN}  user${CL} $admin_email"
    # echo -e "${DGN}  password${CL} iArhP1j7p1P6TA92FA2FMbbUGYqwcYzxC4AVEe12Wbi94FY9gNN62aKyF1shrvG4NycjjX9KfmDQiwkLZH1ZDR9xMjiG2QmoHXi"
    echo -e "${DGN}- you will be prompted to create a user email, and password on (initial) entry...${CL}"
    echo
fi

last_restart=$(docker inspect --format '{{.State.StartedAt}}' npmplus)
if [[ "$npm_restart" == "true" || "$last_restart" < "$(date --date='2 minutes ago' --utc +%Y-%m-%dT%H:%M:%SZ)" ]]; then
    msg_info "${DGN}restarting of NPMplus container...${CL}"
    docker restart crowdsec npmplus >/dev/null
    msg_ok "restarted npmplus container completed ok (all new settings now in place.)"
else
    msg_ok "npmplus has already restarted within the last 2 minutes, no need to restart again."
fi
