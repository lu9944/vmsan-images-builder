#!/bin/bash
set -euo pipefail

DB="/opt/1panel/db/agent.db"
MARKER="/opt/1panel/.register-apps-done"
[ -f "$MARKER" ] && exit 0

echo "=== register: waiting for database ===" >&2
for i in $(seq 1 120); do
    [ -f "$DB" ] && break
    sleep 2
done
if [ ! -f "$DB" ]; then
    echo "ERROR: database not found" >&2
    exit 1
fi

echo "=== register: waiting for app sync ===" >&2
_cnt=0
for i in $(seq 1 120); do
    _cnt=$(sqlite3 "$DB" "SELECT COUNT(*) FROM apps WHERE key IN ('mysql','openresty');" 2>/dev/null || echo 0)
    [ "$_cnt" -ge 2 ] && break
    sleep 5
done
if [ "$_cnt" -lt 2 ]; then
    echo "ERROR: app sync incomplete" >&2
    exit 1
fi

MYSQL_APP_ID=$(sqlite3 "$DB" "SELECT id FROM apps WHERE key='mysql' LIMIT 1;")
OPENRESTY_APP_ID=$(sqlite3 "$DB" "SELECT id FROM apps WHERE key='openresty' LIMIT 1;")

MYSQL_DETAIL_ID=$(sqlite3 "$DB" "SELECT id FROM app_details WHERE app_id=$MYSQL_APP_ID AND version='8.0.46' LIMIT 1;")
OPENRESTY_DETAIL_ID=$(sqlite3 "$DB" "SELECT id FROM app_details WHERE app_id=$OPENRESTY_APP_ID AND version='1.31.1.1-0-noble' LIMIT 1;")

echo "=== register: mysql app_id=$MYSQL_APP_ID detail_id=$MYSQL_DETAIL_ID ===" >&2
echo "=== register: openresty app_id=$OPENRESTY_APP_ID detail_id=$OPENRESTY_DETAIL_ID ===" >&2

MYSQL_EXISTS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM app_installs WHERE name='mysql';" 2>/dev/null || echo 0)
OPENRESTY_EXISTS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM app_installs WHERE name='openresty';" 2>/dev/null || echo 0)

if [ "$MYSQL_EXISTS" -eq 0 ]; then
    echo "=== register: inserting mysql ===" >&2
    _mc=$(sed "s/'/''/g" /opt/1panel/apps/mysql/mysql/docker-compose.yml | tr '\n' ' ')
    _me='{"PANEL_DB_ROOT_PASSWORD":"mysql123456","PANEL_APP_PORT_HTTP":"3306","CONTAINER_NAME":"1Panel-mysql-ppre","CPUS":"0","MEMORY_LIMIT":"0","HOST_IP":"127.0.0.1"}'
    _mp='{"PANEL_DB_ROOT_PASSWORD":"mysql123456","PANEL_DB_ROOT_USER":"root"}'

    sqlite3 "$DB" \
        "INSERT INTO app_installs (created_at,updated_at,name,app_id,app_detail_id,version,param,env,docker_compose,status,description,message,container_name,service_name,http_port,https_port,web_ui,favorite,sort_order) \
         VALUES(datetime('now'),datetime('now'),'mysql',$MYSQL_APP_ID,$MYSQL_DETAIL_ID,'8.0.46','$_mp','$_me','$_mc','Running','','','1Panel-mysql-ppre','mysql',3306,0,'',0,0);"

    _mi=$(sqlite3 "$DB" "SELECT last_insert_rowid();")
    sqlite3 "$DB" \
        "INSERT INTO databases (created_at,updated_at,app_install_id,name,type,version,\"from\",address,port,username,password,description) \
         VALUES(datetime('now'),datetime('now'),$_mi,'mysql','mysql','8.0.46','local','mysql',3306,'root','mysql123456','');"
    echo "=== register: mysql installed (id=$_mi) ===" >&2
fi

if [ "$OPENRESTY_EXISTS" -eq 0 ]; then
    echo "=== register: inserting openresty ===" >&2
    _oc=$(sed "s/'/''/g" /opt/1panel/apps/openresty/openresty/docker-compose.yml | tr '\n' ' ')
    _oe='{"PANEL_APP_PORT_HTTP":"80","PANEL_APP_PORT_HTTPS":"443","WEBSITE_DIR":"/opt/1panel/www","CONTAINER_NAME":"1Panel-openresty-opre","CPUS":"0","MEMORY_LIMIT":"0","HOST_IP":"127.0.0.1","CONTAINER_PACKAGE_URL":"http://archive.ubuntu.com/ubuntu/","RESTY_ADD_PACKAGE_BUILDDEPS":"","RESTY_CONFIG_OPTIONS_MORE":""}'

    sqlite3 "$DB" \
        "INSERT INTO app_installs (created_at,updated_at,name,app_id,app_detail_id,version,env,docker_compose,status,description,message,container_name,service_name,http_port,https_port,web_ui,favorite,sort_order) \
         VALUES(datetime('now'),datetime('now'),'openresty',$OPENRESTY_APP_ID,$OPENRESTY_DETAIL_ID,'1.31.1.1-0-noble','$_oe','$_oc','Running','','','1Panel-openresty-opre','openresty',80,443,'',0,1);"
    echo "=== register: openresty installed ===" >&2
fi

touch "$MARKER"
echo "=== register: done ===" >&2
