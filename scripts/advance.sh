#!/bin/sh
# Move the shop data forward by one step (new orders, status changes ...), like a live system.
#   docker compose exec mysql sh /scripts/advance.sh           apply the next step
#   docker compose exec mysql sh /scripts/advance.sh status    show where you are
export MYSQL_PWD="$MYSQL_ROOT_PASSWORD"
run() { mysql -uroot --batch --skip-column-names "$@"; }

last=$(run -e "SELECT COALESCE(MAX(step), 0) FROM course_meta.applied_steps") || exit 1
total=$(ls /data/deltas/step_*.sql.gz 2>/dev/null | wc -l)
latest() { run -e "SELECT MAX(ordered_at) FROM ecommerce.orders"; }

if [ "$1" = "status" ]; then
    echo "applied $last of $total steps; latest order: $(latest)"
    exit 0
fi

next=$((last + 1))
file=$(printf "/data/deltas/step_%02d.sql.gz" "$next")
if [ ! -f "$file" ]; then
    echo "no more steps (applied $last of $total). Reset: docker compose down -v && docker compose up -d"
    exit 0
fi

echo "applying step $next of $total (latest order before: $(latest)) ..."
zcat "$file" | head -2
# one transaction: the data and the step marker are applied together or not at all
{ echo "START TRANSACTION;"; zcat "$file"
  echo "INSERT INTO course_meta.applied_steps (step) VALUES ($next);"; echo "COMMIT;"; } | run ecommerce || exit 1
echo "done. latest order now: $(latest)"
