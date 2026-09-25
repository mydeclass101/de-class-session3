#!/bin/bash
# Runs once, on the first start (empty volume): restore the `ecommerce` database from ./data.
# Sourced by the MySQL entrypoint, so avoid `set -e` / top-level `exit 0`.

DUMP=/data/ecommerce_base.sql.gz

load_ecommerce() {
    if [ ! -s "$DUMP" ]; then
        echo ">>> $DUMP not found: downloading from $DATA_URL"
        curl -fL --retry 3 --progress-bar -o "$DUMP.part" "$DATA_URL" && mv "$DUMP.part" "$DUMP" || return 1
    fi
    if [ -f /data/ecommerce_base.sql.gz.sha256 ]; then
        echo ">>> checking file integrity"
        # strip CR: git on Windows may check the .sha256 file out with CRLF line endings
        (cd /data && tr -d '\r' < ecommerce_base.sql.gz.sha256 | sha256sum -c -) || { rm -f "$DUMP"; return 1; }
    fi
    echo ">>> restoring ecommerce (takes a few minutes, please wait) ..."
    { echo "SET sql_log_bin = 0;"; zcat "$DUMP"; } | MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot || return 1
    echo ">>> ecommerce restored"
}

if ! load_ecommerce; then
    # MySQL will not re-run init scripts on this volume: keep the container unhealthy (see healthcheck)
    touch /var/lib/mysql/COURSE_DATA_MISSING
    echo ""
    echo "!!! Could not load the course data."
    echo "!!! Download ecommerce_base.sql.gz yourself, put it in the data/ folder, then run:"
    echo "!!!     docker compose down -v"
    echo "!!!     docker compose up -d"
    exit 1
fi
