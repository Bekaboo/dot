function home-backup --description 'Backup home directory'
    borg create --list -v \
            --exclude-from ~/.scripts/borg/exclude.txt \
            borg/home::{hostname}-{user}-{now:%Y-%m-%dT%H:%M:%S.%f} ~
        and borg prune --list -d 60 -w 24 -m 24 -y 10 borg/home
        and borg compact --cleanup-commits borg/home
end
